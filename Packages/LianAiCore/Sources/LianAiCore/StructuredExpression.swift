import Foundation

/// Deterministic list enforcement ported from Android StructuredExpressionFormatter.
public enum StructuredExpression {
  private static let marker = "第[一二三四五六七八九十百千万两0-9]+是|第[一二三四五六七八九十百千万两0-9]+|[一二三四五六七八九十]+是|首先|其次|然后|最后|一方面|另一方面"
  private static let introCount = "[一二三四五六七八九十两0-9]+件事|(?:有|包括)(?:以下)?(?:几|[一二三四五六七八九十两0-9]+)点"
  private static let delimitedIntro = "(?:包括|包含|分别是|分为|原因有|优点有|缺点有|有以下)(?:[一二三四五六七八九十两0-9]+点)?[:：]"
  private static func matches(_ pattern: String, _ text: String) -> [NSRange] {
    (try? NSRegularExpression(pattern: pattern).matches(in: text, range: NSRange(text.startIndex..., in: text)).map(\.range)) ?? []
  }
  private static func trim(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "，,、；;：:")))
  }
  public static func needsStructure(_ text: String) -> Bool {
    let compact = text.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    let count = matches(marker, compact).count
    return count >= 2 || count >= 1 && !matches(introCount, compact).isEmpty ||
      !matches(delimitedIntro, compact).isEmpty && compact.contains { "、,，".contains($0) } ||
      compact.contains("一方面") && compact.contains("另一方面")
  }
  public static func enforce(source: String, polished: String) -> String {
    guard needsStructure(source), matches("(?m)^\\s*\\d+[.、]", polished).isEmpty else { return polished }
    return parse(polished) ?? parse(source) ?? polished
  }
  private static func parse(_ text: String) -> String? {
    let ns = text as NSString
    let markers = matches(marker, text)
    let title: String
    let items: [String]
    if markers.count >= 2 {
      title = trim(ns.substring(to: markers[0].location))
      items = markers.enumerated().map { index, range in
        let start = NSMaxRange(range)
        let end = index + 1 < markers.count ? markers[index + 1].location : ns.length
        return trim(ns.substring(with: NSRange(location: start, length: end - start)))
      }.filter { !$0.isEmpty }
    } else {
      guard let intro = matches(delimitedIntro, text).first else { return nil }
      let prefix = trim(ns.substring(to: intro.location))
      title = prefix.isEmpty ? trim(ns.substring(with: intro)) : prefix
      items = ns.substring(from: NSMaxRange(intro)).components(separatedBy: CharacterSet(charactersIn: "、，,"))
        .map(trim).filter { !$0.isEmpty }
    }
    guard items.count >= 2 else { return nil }
    let heading = title.isEmpty ? "" : trim(title) + "：\n"
    return heading + items.enumerated().map { "\($0.offset + 1).\($0.element)" }.joined(separator: "\n")
  }
}
