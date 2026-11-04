import XCTest
import LianAiCore

@testable import LianAiKeyboard

@MainActor
final class RimeIntegrationTests: XCTestCase {
  func testBundledReadingDataAndEnglishDictionary() {
    XCTAssertEqual(InputLexicon.reading("你好", digits: "64426"), "ni hao")
    XCTAssertEqual(InputLexicon.reading("重庆", digits: "246647464"), "chong qing")
    XCTAssertTrue(InputLexicon.completions("hell", custom: []).contains("hello"))
    XCTAssertTrue(InputLexicon.completions("hellp", custom: []).contains("hello"))
    XCTAssertEqual(
      InputLexicon.completions("he", custom: [], learned: ["hero": 10]).dropFirst().first, "hero")
  }
  func testBundledTwentySixKeyProducesRealChineseCandidatesAndCommits() throws {
    let runtime = RimeRuntime()
    runtime.start(nineKey: false)
    defer { runtime.close() }
    XCTAssertTrue(runtime.ready, runtime.error)
    for key in "nihao" { _ = runtime.key(String(key)) }
    XCTAssertFalse(runtime.preedit.isEmpty)
    XCTAssertTrue(
      runtime.candidates.contains { $0.text.contains("你好") },
      "Expected 你好 in bundled Rime candidates")
    let candidate = try XCTUnwrap(runtime.candidates.first { $0.text.contains("你好") })
    XCTAssertEqual(runtime.choose(candidate.index), candidate.text)
  }
  func testBundledNineKeyAndDeletePreserveComposition() throws {
    let runtime = RimeRuntime()
    runtime.start(nineKey: true)
    defer { runtime.close() }
    XCTAssertTrue(runtime.ready, runtime.error)
    _ = runtime.key("6")
    _ = runtime.key("4")
    XCTAssertFalse(runtime.candidates.isEmpty)
    XCTAssertFalse(runtime.displayPreedit.contains(where: \.isNumber))
    XCTAssertTrue(runtime.candidates.contains { $0.text == "你" })
    _ = runtime.delete()
    XCTAssertEqual(runtime.raw, "6")
    runtime.clear()
    XCTAssertTrue(runtime.preedit.isEmpty)
  }
  func testCandidatePaginationDoesNotCommitOrMutateInput() {
    let runtime = RimeRuntime()
    runtime.start(nineKey: true)
    defer { runtime.close() }
    _ = runtime.key("6")
    _ = runtime.key("4")
    let before = runtime.raw
    runtime.more()
    XCTAssertEqual(runtime.raw, before)
    XCTAssertGreaterThan(runtime.candidates.count, 9)
  }
}

extension RimeIntegrationTests {
  func testBundledAndroidPredictionIndexesProduceRealChineseAndEnglishSuggestions() throws {
    let base = try XCTUnwrap(InputLexicon.predictionBase)
    let enhanced = try XCTUnwrap(InputLexicon.predictionEnhanced)
    XCTAssertEqual(base.count, 90_217)
    XCTAssertEqual(enhanced.count, 104_730)
    let values = PredictionEngine.suggestions(tokens: ["你好"], base: base, enhanced: enhanced, learned: [])
    XCTAssertFalse(values.isEmpty)
    XCTAssertLessThanOrEqual(values.count, 6)
    XCTAssertEqual(PredictionEngine.suggestions(tokens: ["good"], base: base, enhanced: enhanced, learned: []).first, "morning")
  }
}

@MainActor
final class KeyboardTypingLatencyTests: XCTestCase {
  func testBundledT9KeyAndCandidateWindowLatency() {
    let runtime = RimeRuntime()
    let startup = ProcessInfo.processInfo.systemUptime
    runtime.start(nineKey: true)
    let startupMs = (ProcessInfo.processInfo.systemUptime - startup) * 1000
    defer { runtime.close() }
    XCTAssertTrue(runtime.ready, runtime.error)
    var keys: [Double] = [], windows: [Double] = []
    for word in ["64426", "9664486", "744543", "246647464", "2345464", "9434878"] {
      runtime.clear()
      for digit in word {
        let start = ProcessInfo.processInfo.systemUptime
        _ = runtime.key(String(digit))
        let keyed = ProcessInfo.processInfo.systemUptime
        runtime.more()
        let expanded = ProcessInfo.processInfo.systemUptime
        keys.append((keyed - start) * 1000)
        windows.append((expanded - keyed) * 1000)
      }
      XCTAssertFalse(runtime.candidates.isEmpty)
    }
    func percentile(_ values: [Double], _ p: Double) -> Double {
      let sorted = values.sorted(); return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
    }
    print("TYPING_LATENCY startup_ms=\(startupMs) key_p50_ms=\(percentile(keys, 0.5)) key_p95_ms=\(percentile(keys, 0.95)) key_max_ms=\(keys.max()!) window_p50_ms=\(percentile(windows, 0.5)) window_p95_ms=\(percentile(windows, 0.95)) window_max_ms=\(windows.max()!) count=\(keys.count)")
  }
}

extension RimeIntegrationTests {
  func testCachedReadingsKeepPolyphonicContextAndIndexedEnglishRanking() {
    for _ in 0..<3 {
      XCTAssertEqual(InputLexicon.reading("重", digits: "24664"), "chong")
      XCTAssertEqual(InputLexicon.reading("重", digits: "94664"), "zhong")
      XCTAssertTrue(InputLexicon.completions("HEL", custom: []).contains("HELLO"))
      XCTAssertTrue(InputLexicon.completions("hellp", custom: []).contains("hello"))
      XCTAssertEqual(InputLexicon.completions("he", custom: [], learned: ["hero": 10]).dropFirst().first, "hero")
      XCTAssertEqual(InputLexicon.completions("he", custom: ["Hero", "hero"]).filter { $0.lowercased() == "hero" }.count, 1)
      XCTAssertTrue(InputLexicon.completions("thank y", custom: []).contains("thank you"))
    }
  }
}
