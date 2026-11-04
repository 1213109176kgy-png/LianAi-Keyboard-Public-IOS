import Foundation

public enum OutputRules {
  public static func cleanSymbols(_ value: String) -> String {
    func replace(_ text: String, _ pattern: String, _ replacement: String) -> String {
      text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
    var text = replace(value.replacingOccurrences(of: "\r\n", with: "\n"), "[\\u00A0\\t\\r]+", " ")
    text = text.components(separatedBy: "\n").map {
      replace(replace($0, " {2,}", " "), " +([，。！？、；：,.!?;:])", "$1")
        .trimmingCharacters(in: .whitespaces)
    }.joined(separator: "\n")
    text = replace(text, "\\n{3,}", "\n\n")
    text = replace(text, "([（(【\\[])[\\s]+", "$1")
    text = replace(text, "[\\s]+([）)】\\]])", "$1")
    let regex = try! NSRegularExpression(pattern: "[，。！？、；：,.!?;:]{2,}")
    for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
      guard let range = Range(match.range, in: text) else { continue }
      let punctuation = String(text[range])
      let priorities = [("？?", "？"), ("！!", "！"), ("。.", "。"), ("；;", "；"), ("：:", "："), ("、", "、")]
      let replacement = priorities.first { pair in punctuation.contains { pair.0.contains($0) } }?.1 ?? "，"
      text.replaceSubrange(range, with: replacement)
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  public static func transcript(_ value: String) -> String {
    value.replacingOccurrences(
      of: "(?i)</?(chinese|english|mandarin|cantonese|zh|en|transcript|audio)>", with: "",
      options: .regularExpression
    )
    .replacingOccurrences(
      of: "(?i)(?<=[\\u4E00-\\u9FFF])\\s*null\\s*$", with: "", options: .regularExpression
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
  }
  public static func punctuation(_ value: String, preference: String) -> String {
    let clean = cleanSymbols(value)
    switch preference {
    case "空格代替标点":
      return clean.components(separatedBy: "\n").map {
        $0.replacingOccurrences(
          of: "[，。！？、；：,.!?;:…—()（）\\[\\]{}\"'“”]+", with: " ", options: .regularExpression
        )
        .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
      }.joined(separator: "\n")
    case "句末不添加标点":
      return clean.replacingOccurrences(
        of: "[\\s，。！？、；：,.!?;:…—]+$", with: "", options: .regularExpression)
    default: return clean
    }
  }
}
public enum ThinkingPolicy {
  public enum Control: Sendable { case available, required, unsupported }
  public static func control(url: URL, model: String) -> Control {
    let id = model.lowercased()
    let host = url.host?.lowercased() ?? ""
    func domain(_ value: String) -> Bool { host == value || host.hasSuffix("." + value) }
    func matches(_ pattern: String) -> Bool {
      id.range(of: pattern, options: .regularExpression) != nil
    }
    if id.contains("asr") || id.contains("tts") { return .unsupported }
    if domain("deepseek.com") { return id == "deepseek-reasoner" ? .required : .available }
    if domain("xiaomimimo.com") { return matches("^mimo-v2[.-]") ? .available : .unsupported }
    if domain("bigmodel.cn") || domain("z.ai") {
      if matches("^glm-5\\.3($|-)") { return .required }
      return matches("^glm-(4\\.[567]|5($|[.-]))") ? .available : .unsupported
    }
    if domain("moonshot.cn") || domain("moonshot.ai") || domain("kimi.ai") {
      if matches("^kimi-k(3|2\\.7)") || id.contains("thinking") { return .required }
      return matches("^kimi-k2\\.[56]($|-)") ? .available : .unsupported
    }
    return .unsupported
  }
}
