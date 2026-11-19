import Foundation

public enum KnowledgeMarkdown {
  public struct Block: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case heading(Int), paragraph, quote, code, divider }
    public let id: Int
    public let kind: Kind
    public let text: String
  }
  /// Local text only. Tables become full-width labelled rows, matching Android.
  public static func parse(_ source: String) -> [Block] {
    let lines = source.components(separatedBy: .newlines)
    var result: [Block] = []; var index = 0
    func add(_ kind: Block.Kind, _ text: String) { result.append(Block(id: result.count, kind: kind, text: text)) }
    func cells(_ line: String) -> [String] {
      var value = line.trimmingCharacters(in: .whitespaces)
      if value.hasPrefix("|") { value.removeFirst() }
      if value.hasSuffix("|") { value.removeLast() }
      return value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    while index < lines.count {
      let line = lines[index].trimmingCharacters(in: .whitespaces)
      index += 1
      if line.isEmpty { continue }
      if line.hasPrefix("```") || line.hasPrefix("~~~") {
        let fence = String(line.prefix(3)); var code: [String] = []
        while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
          code.append(lines[index]); index += 1
        }
        if index < lines.count { index += 1 }
        add(.code, code.joined(separator: "\n")); continue
      }
      if line.contains("|"), index < lines.count,
        lines[index].range(of: #"^\s*\|?\s*:?-{3,}:?\s*\|"#, options: .regularExpression) != nil {
        let headers = cells(line); index += 1
        while index < lines.count && lines[index].contains("|") && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
          let row = cells(lines[index]); index += 1
          var labelled: [String] = []
          for (column, value) in row.enumerated() {
            let title = column < headers.count ? headers[column] : "第 \(column+1) 列"
            labelled.append("**\(title)**：\(value)")
          }
          add(.paragraph, labelled.joined(separator: "\n"))
        }
        continue
      }
      if let match = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
        let level = line[match].filter { $0 == "#" }.count
        add(.heading(level), String(line[match.upperBound...])); continue
      }
      if ["---", "***", "___"].contains(line) { add(.divider, ""); continue }
      if line.hasPrefix(">") { add(.quote, String(line.dropFirst()).trimmingCharacters(in: .whitespaces)); continue }
      var text = line
      if text.hasPrefix("- [ ] ") { text = "☐ " + text.dropFirst(6) }
      else if text.lowercased().hasPrefix("- [x] ") { text = "☑ " + text.dropFirst(6) }
      else if text.hasPrefix("- ") || text.hasPrefix("* ") { text = "• " + text.dropFirst(2) }
      // Foundation inline Markdown is rendered as text; images cannot load URLs.
      text = text.replacingOccurrences(of: #"!\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
      add(.paragraph, text)
    }
    return result
  }
}
