import Foundation

public struct PredictionLearning: Codable, Sendable {
  public var context: String
  public var target: String
  public var useCount: Int
  public var lastUsedAt: Double
  public init(context: String, target: String, useCount: Int, lastUsedAt: Double) {
    self.context = context; self.target = target; self.useCount = useCount; self.lastUsedAt = lastUsedAt
  }
}
/// Reads Android VTP1 packs without materializing all target strings in the keyboard process.
public struct PredictionIndex: Sendable {
  private let data: Data
  private let offsets: [String: Int]
  public var count: Int { offsets.count }
  public init(data: Data) throws {
    self.data = data
    var cursor = 0
    func integer(_ bytes: Int) throws -> Int {
      guard cursor <= data.count - bytes else { throw ClientError.message("联想词典格式无效") }
      defer { cursor += bytes }
      return (0..<bytes).reduce(0) { $0 | Int(data[cursor + $1]) << ($1 * 8) }
    }
    func string() throws -> String {
      let length = try integer(2)
      guard cursor <= data.count - length,
        let value = String(data: data[cursor..<cursor + length], encoding: .utf8) else { throw ClientError.message("联想词典格式无效") }
      cursor += length
      return value
    }
    guard try integer(4) == 0x31505456 else { throw ClientError.message("联想词典格式无效") }
    let count = try integer(4)
    guard count <= 1_000_000 else { throw ClientError.message("联想词典格式无效") }
    var index: [String: Int] = [:]
    index.reserveCapacity(count)
    for _ in 0..<count {
      let context = try string()
      index[context] = cursor
      let entries = try integer(1)
      guard entries <= 8 else { throw ClientError.message("联想词典格式无效") }
      for _ in 0..<entries { _ = try string(); _ = try integer(4) }
    }
    guard cursor == data.count else { throw ClientError.message("联想词典格式无效") }
    offsets = index
  }
  public func entries(for context: String) -> [(String, Double)] {
    guard var cursor = offsets[context] else { return [] }
    let count = Int(data[cursor]); cursor += 1
    var result: [(String, Double)] = []
    for _ in 0..<count {
      let length = Int(data[cursor]) | Int(data[cursor + 1]) << 8; cursor += 2
      let text = String(decoding: data[cursor..<cursor + length], as: UTF8.self); cursor += length
      let weight = (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[cursor + $1]) << ($1 * 8) }; cursor += 4
      result.append((text, Double(Int32(bitPattern: weight))))
    }
    return result
  }
}
public enum PredictionEngine {
  public static let separator = "\u{001f}"
  private static func matches(_ value: String, _ regex: String) -> Bool { value.range(of: regex, options: .regularExpression) != nil }
  public static func sensitive(_ value: String) -> Bool {
    value.utf16.count > 64 || matches(value, "^\\d+$") || value.contains("@") || value.contains("://") || matches(value, "^[A-Za-z0-9_-]{16,}$")
  }
  public static func learnable(_ value: String) -> Bool {
    (1...32).contains(value.utf16.count) && !matches(value, "^\\d+$") && !value.contains("@") && !value.contains("://")
  }
  public static func tokens(_ text: String) -> [String] {
    guard !text.isEmpty, !sensitive(text), let regex = try? NSRegularExpression(pattern: "[\\p{Han}]{1,8}|[A-Za-z][A-Za-z0-9._+-]*|[^\\s]") else { return [] }
    return Array(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
      Range($0.range, in: text).map { String(text[$0]).lowercased() }
    }.filter(learnable).suffix(16))
  }
  public static func contexts(_ tokens: [String]) -> [String] {
    guard let last = tokens.last else { return [] }
    var values = tokens.count >= 2 ? [tokens[tokens.count - 2] + separator + last, last] : [last]
    for length in stride(from: min(4, last.count), through: 1, by: -1) { values.append(String(last.suffix(length))) }
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
  }
  public static func transitions(previous: [String], appended: [String]) -> [(String, String)] {
    guard !appended.isEmpty else { return [] }
    let combined = Array((previous + appended).suffix(16))
    let first = max(1, combined.count - appended.count)
    guard first < combined.count else { return [] }
    var result: [(String, String)] = []
    for index in first..<combined.count {
      result.append((combined[index - 1], combined[index]))
      if index >= 2 { result.append((combined[index - 2] + separator + combined[index - 1], combined[index])) }
    }
    return result
  }
  public static func suggestions(tokens: [String], base: PredictionIndex?, enhanced: PredictionIndex?, learned: [PredictionLearning]) -> [String] {
    let contexts = contexts(tokens)
    guard !contexts.isEmpty else { return [] }
    var scores: [String: (String, Double, Int)] = [:]
    var sequence = 0
    func add(_ text: String, _ score: Double) {
      guard !text.isEmpty, !sensitive(text) else { return }
      let key = text.lowercased()
      if let current = scores[key], current.1 >= score { return }
      scores[key] = (text, score, sequence); sequence += 1
    }
    for (index, context) in contexts.enumerated() {
      let boost = index == 0 ? 4_000_000.0 : 200_000.0
      for (text, weight) in base?.entries(for: context) ?? [] { add(text, boost + weight) }
      for (text, weight) in enhanced?.entries(for: context) ?? [] { add(text, boost + 15_000 + weight) }
      for (index, phrase) in (english[context] ?? []).enumerated() { add(phrase, boost + 500_000 - Double(index * 100)) }
    }
    for item in learned {
      guard let position = contexts.firstIndex(of: item.context), learnable(item.target) else { continue }
      let boost = position == 0 ? 5_000_000.0 : 300_000.0
      add(item.target, boost + log(Double(max(0, item.useCount)) + 1) * 100_000 + item.lastUsedAt / 1e11)
    }
    if tokens.last == "http" { add("s://", 900_000) }
    if tokens.last == "https" { add("://", 900_000) }
    return Array(scores.values.sorted { $0.1 == $1.1 ? $0.2 < $1.2 : $0.1 > $1.1 }.prefix(6).map(\.0))
  }
  public static func appendSpace(_ text: String) -> Bool { matches(text, "^[A-Za-z][A-Za-z'-]*$") }
  private static let english = [
    "hello": ["there", "world"], "good": ["morning", "afternoon", "evening"], "thank": ["you"],
    "thank\u{001f}you": ["very much"], "please": ["let me know"], "let": ["me know"],
    "let\u{001f}me": ["know"], "see": ["you soon"], "how": ["are you"],
    "i": ["think", "would", "will"], "we": ["can", "will", "should"],
  ]
}
