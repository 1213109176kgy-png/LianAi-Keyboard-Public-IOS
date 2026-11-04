import Foundation
import LianAiCore

@MainActor
enum InputLexicon {
  static let predictionBase = loadPrediction("prediction-base")
  static let predictionEnhanced = loadPrediction("prediction-enhanced")
  private static func loadPrediction(_ name: String) -> PredictionIndex? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "bin", subdirectory: "InputData"),
      let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
    return try? PredictionIndex(data: data)
  }

  static let readings: [Unicode.Scalar: [String]] = {
    guard
      let url = Bundle.main.url(
        forResource: "pinyin", withExtension: "txt", subdirectory: "InputData"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { return [:] }
    var result: [Unicode.Scalar: [String]] = [:]
    for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("U+") {
      let fields = line.split(separator: ":", maxSplits: 1)
      guard fields.count == 2, let value = UInt32(fields[0].dropFirst(2), radix: 16),
        let scalar = Unicode.Scalar(value)
      else { continue }
      result[scalar] = fields[1].split(separator: "#", maxSplits: 1)[0]
        .split(separator: ",").map {
          $0.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
            .lowercased().filter { $0.isASCII && $0.isLetter }
        }.filter { !$0.isEmpty }
    }
    return result
  }()
  static let english: [String] = {
    guard
      let url = Bundle.main.url(
        forResource: "en.dict", withExtension: "yaml", subdirectory: "InputData"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { return [] }
    return text.split(whereSeparator: \.isNewline).compactMap { line in
      guard !line.hasPrefix("#"), line.contains("\t"), let word = line.split(separator: "\t").first,
        word.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "'" || $0 == "-") })
      else { return nil }
      return String(word)
    }
  }()
  private struct ReadingKey: Hashable { let text: String; let digits: String }
  private static var readingCache: [ReadingKey: String] = [:]
  private static var codeCache: [String: String] = [:]
  static func prepareChineseReadings() { _ = readings }
  static func prepareEnglishCompletions() { _ = englishIndex }
  static func code(_ value: String) -> String {
    if let cached = codeCache[value] { return cached }
    let groups = ["abc", "def", "ghi", "jkl", "mno", "pqrs", "tuv", "wxyz"]
    let result = value.lowercased().compactMap { letter in
      groups.firstIndex { $0.contains(letter) }.map { String($0 + 2) }
    }.joined()
    if codeCache.count >= 2048 { codeCache.removeAll(keepingCapacity: true) }
    codeCache[value] = result
    return result
  }
  static func reading(_ text: String, digits: String) -> String {
    let key = ReadingKey(text: text, digits: digits)
    if let cached = readingCache[key] { return cached }
    var remaining = digits
    let result = text.unicodeScalars.compactMap { scalar -> String? in
      guard let variants = readings[scalar], !variants.isEmpty else { return nil }
      let reading =
        variants.first {
          let code = code($0)
          return remaining.hasPrefix(code) || code.hasPrefix(remaining)
        } ?? variants[0]
      remaining = String(remaining.dropFirst(min(remaining.count, code(reading).count)))
      return reading
    }.joined(separator: " ")
    if readingCache.count >= 4096 { readingCache.removeAll(keepingCapacity: true) }
    readingCache[key] = result
    return result
  }
  static let common = [
    "the", "be", "to", "of", "and", "a", "in", "that", "have", "i", "it", "for", "not", "on",
    "with", "he", "as", "you", "do", "at", "this", "is", "hello", "please", "thanks", "thank", "we",
    "will", "can", "could", "should", "would", "project", "meeting", "message", "today", "tomorrow",
  ]
  static let phrases = [
    "thank you", "please let me know", "let me know", "as soon as possible", "for your reference",
    "best regards", "good morning", "good afternoon", "happy to help", "sounds good",
    "see you soon", "talk to you later",
  ]
  private struct EnglishIndex {
    let words: [String]
    let prefixes: [String: [Int]]
    let lengths: [Int: [Int]]
  }
  private static let englishIndex: EnglishIndex = {
    let words = english + phrases
    var prefixes: [String: [Int]] = [:], lengths: [Int: [Int]] = [:]
    for (index, word) in words.enumerated() {
      let lower = word.lowercased()
      for size in 1...min(2, lower.count) { prefixes[String(lower.prefix(size)), default: []].append(index) }
      lengths[lower.count, default: []].append(index)
    }
    return EnglishIndex(words: words, prefixes: prefixes, lengths: lengths)
  }()
  private static let commonScores = Dictionary(uniqueKeysWithValues: common.enumerated().map { ($0.element, 50000 - $0.offset * 500) })
  static func completions(_ prefix: String, custom: [String], learned: [String: Int] = [:])
    -> [String]
  {
    let query = prefix.lowercased()
    var scores: [String: Double] = [:]
    func score(_ word: String) -> Double {
      if let value = scores[word] { return value }
      let lower = word.lowercased()
      let value = Double(learned[lower] ?? 0) * 100000 + Double(commonScores[lower] ?? 0) - Double(word.count) * 0.05
      scores[word] = value
      return value
    }
    func sorted(_ values: [String]) -> [String] {
      values.sorted {
        score($0) == score($1)
          ? ($0.count == $1.count ? $0 < $1 : $0.count < $1.count) : score($0) > score($1)
      }
    }
    let index = englishIndex
    let indexPrefix = String(query.prefix(2))
    let positions = query.isEmpty ? Array(index.words.indices) : index.prefixes[indexPrefix] ?? []
    let matches = Array(sorted(positions.map { index.words[$0] }.filter { $0.lowercased().hasPrefix(query) }).prefix(15))
    let corrected: [String]
    if matches.isEmpty && query.count >= 3 {
      let nearby = ((query.count - 1)...(query.count + 1)).flatMap { index.lengths[$0] ?? [] }
      corrected = Array(sorted(nearby.map { index.words[$0] }.filter { oneEdit(query, $0.lowercased()) }).prefix(6))
    } else { corrected = [] }
    let customMatches = custom.filter { $0.lowercased().hasPrefix(query) }
    var seen: Set<String> = []
    return (customMatches + [prefix] + matches + corrected).filter {
      seen.insert($0.lowercased()).inserted
    }.map { word in
      prefix == prefix.uppercased()
        ? word.uppercased()
        : prefix.first?.isUppercase == true ? word.prefix(1).uppercased() + word.dropFirst() : word
    }
  }
  private static func oneEdit(_ left: String, _ right: String) -> Bool {
    let a = Array(left)
    let b = Array(right)
    guard abs(a.count - b.count) <= 1 else { return false }
    var i = 0
    var j = 0
    var changes = 0
    while i < a.count && j < b.count {
      if a[i] == b[j] {
        i += 1
        j += 1
        continue
      }
      changes += 1
      if changes > 1 { return false }
      if a.count > b.count {
        i += 1
      } else if b.count > a.count {
        j += 1
      } else {
        i += 1
        j += 1
      }
    }
    return changes + (i < a.count || j < b.count ? 1 : 0) <= 1
  }
}
