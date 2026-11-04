import XCTest
@testable import LianAiKeyboard

nonisolated private final class SlowClickPlayback: KeyboardClickPlayback, @unchecked Sendable {
  let started: XCTestExpectation
  let release = DispatchSemaphore(value: 0)
  let played: XCTestExpectation
  init(started: XCTestExpectation, played: XCTestExpectation) {
    self.started = started; self.played = played
  }
  func prepare() -> Bool {
    XCTAssertFalse(Thread.isMainThread)
    started.fulfill()
    _ = release.wait(timeout: .now() + 3)
    return true
  }
  func play(volume: Float) -> Bool {
    XCTAssertFalse(Thread.isMainThread)
    XCTAssertEqual(volume, 0.35)
    played.fulfill()
    return true
  }
}
@MainActor
final class KeyboardClickAudioTests: XCTestCase {
  func testBlockedAudioPreparationDoesNotBlockKeyInputOrReplayExpiredClick() async {
    let started = expectation(description: "Audio preparation started off main")
    let played = expectation(description: "Only the fresh click plays")
    played.assertForOverFulfill = true
    let backend = SlowClickPlayback(started: started, played: played)
    let audio = KeyboardClickAudio(makePlayback: { backend })
    audio.prepare()
    await fulfillment(of: [started], timeout: 2)
    audio.play(volume: 0.35)
    var text = ""
    let key = InputKey("a", background: .white, foreground: .black) { text += "a" }
    key.activatesOnTouchDown = true
    key.sendActions(for: .touchDown)
    XCTAssertEqual(text, "a", "音频仍在阻塞时，主线程必须可以继续输入")
    try? await Task.sleep(for: .milliseconds(120))
    backend.release.signal()
    // Give the serial queue a fresh request after discarding the stale one.
    audio.play(volume: 0.35)
    await fulfillment(of: [played], timeout: 2)
  }
}
