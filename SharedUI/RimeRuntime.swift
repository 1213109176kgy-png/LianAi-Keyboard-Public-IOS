import Foundation
import KeyboardCore
import LianAiCore
import RimeBridgeObjC

struct InputCandidate {
  let text: String
  let comment: String
  let index: Int
}
@MainActor
final class RimeRuntime {
  private let bridge = RimeSessionManager()
  private(set) var ready = false
  private(set) var error = ""
  private(set) var preedit = ""
  private(set) var displayPreedit = ""
  private(set) var raw = ""
  private(set) var candidates: [InputCandidate] = []
  private var nineKey = true
  private var userDirectory: URL?
  // Explicit legacy deinit avoids the synthesized isolated-deinit path that
  // crashes in TaskLocal::StopLookupScope on older iOS runtimes (swift#88036).
  // Engine shutdown remains in close(), on the main actor.
  deinit {}
  func start(nineKey: Bool, bundle: Bundle = .main) {
    self.nineKey = nineKey
    if nineKey { InputLexicon.prepareChineseReadings() }
    guard !ready else {
      selectLayout(nineKey)
      return
    }
    do {
      guard let shared = bundle.url(forResource: "Rime", withExtension: nil) else {
        throw ClientError.message("内置词典缺失，请重新安装")
      }
      let user = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LianAiRimeUser")
      let build = user.appendingPathComponent("build")
      try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
      let defaults = UserDefaults(suiteName: Product.group)
      if let stamp = defaults?.string(forKey: "clearRimeLearning"),
        UserDefaults.standard.string(forKey: "appliedClearRime") != stamp
      {
        for file in try FileManager.default.contentsOfDirectory(
          at: user, includingPropertiesForKeys: nil) where file.lastPathComponent.contains("userdb")
        { try FileManager.default.removeItem(at: file) }
        UserDefaults.standard.set(stamp, forKey: "appliedClearRime")
      }
      let grammar = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: Product.group)?.appendingPathComponent(
          "wanxiang-lts-zh-hans.gram")
      let useGrammar = grammar.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
      for name in ["default", "weike_pinyin", "weike_t9"] {
        let source = shared.appendingPathComponent(
          name == "default" ? "default.yaml" : name + ".schema.yaml")
        var text = try String(contentsOf: source, encoding: .utf8)
        if useGrammar && name != "default" {
          text = text.replacingOccurrences(
            of: "translator:\n",
            with: "translator:\n  contextual_suggestions: false\n  max_homophones: 8\n")
          text +=
            "\ngrammar:\n  language: wanxiang-lts-zh-hans\n  collocation_max_length: 6\n  collocation_min_length: 3\n  collocation_penalty: -14\n  non_collocation_penalty: -6\n  weak_collocation_penalty: -100\n  rear_penalty: -20\n"
        }
        let destination = build.appendingPathComponent(source.lastPathComponent)
        if (try? String(contentsOf: destination, encoding: .utf8)) != text {
          try text.write(to: destination, atomically: true, encoding: .utf8)
        }
      }
      if useGrammar, let grammar {
        let link = user.appendingPathComponent(grammar.lastPathComponent)
        if !FileManager.default.fileExists(atPath: link.path) {
          try FileManager.default.createSymbolicLink(at: link, withDestinationURL: grammar)
        }
      }
      guard bridge.setup(withSharedDataDir: shared.path, userDataDir: user.path),
        bridge.initializeEngine(), bridge.createSession(),
        bridge.selectSchema(nineKey ? "weike_t9" : "weike_pinyin")
      else { throw ClientError.message("拼音引擎无法启动，请重新打开键盘") }
      userDirectory = user
      ready = true
      error = ""
    } catch {
      self.error = error.localizedDescription
      ready = false
    }
  }
  func selectLayout(_ nine: Bool) {
    nineKey = nine
    bridge.clearComposition()
    if ready { ready = bridge.selectSchema(nine ? "weike_t9" : "weike_pinyin") }
    consume(bridge.currentOutput())
  }
  func key(_ text: String) -> String? {
    guard ready else { return nil }
    guard let scalar = text.unicodeScalars.first else { return nil }
    return consume(bridge.processKey(Int32(scalar.value), modifiers: 0))
  }
  func delete() -> String? { consume(bridge.deleteBackward()) }
  func choose(_ index: Int) -> String? {
    consume(bridge.selectCandidate(atGlobalIndex: Int32(index)))
  }
  func clear() {
    bridge.clearComposition()
    raw = ""
    preedit = ""
    displayPreedit = ""
    candidates = []
  }
  func close() {
    bridge.finalize()
    ready = false
    raw = ""
    preedit = ""
    displayPreedit = ""
    candidates = []
  }
  func more() {
    let window = bridge.candidates(from: 0, limit: 150)
    candidates = parseCandidates(window["candidates"])
  }
  @discardableResult private func consume(_ output: [AnyHashable: Any]) -> String? {
    let previousRaw = raw
    let previousDisplay = displayPreedit
    preedit = output["preedit"] as? String ?? ""
    raw = output["rawInput"] as? String ?? ""
    candidates = parseCandidates(output["candidates"])
    displayPreedit = preedit
    if nineKey, !raw.isEmpty, raw.contains(where: \.isNumber) {
      let code = raw.filter(\.isNumber)
      let readings = candidates.map {
        InputLexicon.reading($0.text, digits: code).filter(\.isLetter)
      }.filter { !$0.isEmpty }
      if let exact = readings.first(where: { InputLexicon.code($0) == code }) {
        displayPreedit = exact
      } else if let prefix = readings.first(where: { InputLexicon.code($0).hasPrefix(code) }) {
        displayPreedit = String(prefix.prefix(code.count))
      } else if preedit.isEmpty || preedit.contains(where: \.isNumber) {
        let previousCode = previousRaw.filter(\.isNumber)
        displayPreedit =
          !previousCode.isEmpty && code.hasPrefix(previousCode) && !previousDisplay.isEmpty
          ? previousDisplay.filter { $0.isLetter || $0 == " " }.trimmingCharacters(in: .whitespaces)
            + "…"
          : readings.first.map { $0 + "…" } ?? "…"
      }
    }
    return (output["commit"] as? String).flatMap { $0.isEmpty ? nil : $0 }
  }
  private func parseCandidates(_ value: Any?) -> [InputCandidate] {
    (value as? [[String: Any]] ?? []).enumerated().compactMap { i, item in
      guard let text = item["text"] as? String else { return nil }
      return InputCandidate(
        text: text, comment: item["comment"] as? String ?? "",
        index: (item["globalIndex"] as? NSNumber)?.intValue ?? i)
    }
  }
}
