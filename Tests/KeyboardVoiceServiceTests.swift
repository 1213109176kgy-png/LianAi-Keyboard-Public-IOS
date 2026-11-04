import LianAiCore
import XCTest
@testable import LianAiKeyboard

@MainActor
private final class CaptureSpy: KeyboardVoiceCapture {
  var starts = 0, finishes = 0, cancelled = 0, disarmed = 0
  var update: (@MainActor @Sendable (String, Bool) -> Void)?
  var failure: (@MainActor @Sendable (String) -> Void)?
  func arm() async throws {}
  func begin(update: @escaping @MainActor @Sendable (String, Bool) -> Void,
    failure: @escaping @MainActor @Sendable (String) -> Void) throws {
    starts += 1; self.update = update; self.failure = failure
  }
  func finish() { finishes += 1 }
  func cancelUtterance() { cancelled += 1 }
  func disarm() { disarmed += 1 }
}
@MainActor
final class KeyboardVoiceServiceTests: XCTestCase {
  private func fixture() throws -> (KeyboardVoiceMailbox, CaptureSpy, KeyboardVoiceService) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let mailbox = try KeyboardVoiceMailbox(directory: directory)
    let capture = CaptureSpy()
    return (mailbox, capture, KeyboardVoiceService(mailbox: mailbox, capture: capture))
  }
  func testRealMailboxStartFinishResultAcknowledgeAndIdleCaptureBoundary() async throws {
    let (mailbox, capture, service) = try fixture()
    defer { service.stop(); try? FileManager.default.removeItem(at: mailbox.directory) }
    await service.enable()
    XCTAssertEqual(capture.starts, 0, "Arming must not start a speech recognition request")
    let id = UUID(), session = service.state.session, time = Date()
    try mailbox.send(.init(session: session, request: id, action: .start, createdAt: time))
    try mailbox.send(.init(session: session, request: id, action: .finish, createdAt: time.addingTimeInterval(0.001)))
    service.tick()
    XCTAssertEqual(capture.starts, 1); XCTAssertEqual(capture.finishes, 1)
    XCTAssertEqual(mailbox.read()?.phase, .processing)
    capture.update?("明天见。", true)
    XCTAssertEqual(mailbox.read()?.phase, .result)
    XCTAssertEqual(mailbox.read()?.text, "明天见。")
    try mailbox.send(.init(session: session, request: id, action: .acknowledge)); service.tick()
    XCTAssertEqual(mailbox.read()?.phase, .ready); XCTAssertEqual(mailbox.read()?.text, "")
  }
  func testStaleAndWrongSessionCommandsAndLateCallbacksCannotInsert() async throws {
    let (mailbox, capture, service) = try fixture()
    defer { service.stop(); try? FileManager.default.removeItem(at: mailbox.directory) }
    await service.enable(); let session = service.state.session, id = UUID()
    try mailbox.send(.init(session: UUID(), request: id, action: .start))
    try mailbox.send(.init(session: session, request: id, action: .start, createdAt: Date().addingTimeInterval(-20)))
    service.tick(); XCTAssertEqual(capture.starts, 0)
    try mailbox.send(.init(session: session, request: id, action: .start)); service.tick()
    let lateUpdate = capture.update
    try mailbox.send(.init(session: session, request: id, action: .cancel)); service.tick()
    lateUpdate?("不能出现", true)
    XCTAssertEqual(service.state.phase, .ready); XCTAssertEqual(service.state.text, "")
    try mailbox.send(.init(session: session, request: UUID(), action: .finish)); service.tick()
    XCTAssertEqual(capture.finishes, 0)
  }
  func testLostKeyboardLeaseCancelsAudioAndErasesTranscript() async throws {
    let (mailbox, capture, service) = try fixture()
    defer { service.stop(); try? FileManager.default.removeItem(at: mailbox.directory) }
    await service.enable()
    try mailbox.send(.init(session: service.state.session, request: UUID(), action: .start)); service.tick()
    capture.update?("这段不能残留", false)
    service.tick(now: Date().addingTimeInterval(5))
    XCTAssertEqual(service.state.phase, .ready); XCTAssertEqual(service.state.text, "")
    XCTAssertGreaterThan(capture.cancelled, 0)
  }
  func testFailureEmptySpeechAndRecordingTimeLimit() async throws {
    let (mailbox, capture, service) = try fixture()
    defer { service.stop(); try? FileManager.default.removeItem(at: mailbox.directory) }
    await service.enable(); let session = service.state.session
    func start() throws {
      try mailbox.send(.init(session: session, request: UUID(), action: .start)); service.tick()
    }
    try start(); capture.failure?("无网络")
    XCTAssertEqual(service.state.phase, .failed)
    try start(); capture.update?("", true)
    XCTAssertEqual(service.state.phase, .failed)
    XCTAssertTrue(service.state.message.contains("没有识别"))
    try start()
    let future = Date().addingTimeInterval(61)
    try mailbox.send(.init(session: session, request: service.state.request!, action: .keepAlive, createdAt: future))
    service.tick(now: future)
    XCTAssertEqual(service.state.phase, .processing); XCTAssertEqual(capture.finishes, 1)
    service.stop(); XCTAssertEqual(service.state.phase, .stopped)
    XCTAssertGreaterThan(capture.disarmed, 0)
  }
  func testLongIdleKeepsSessionLiveAndAllowsAnotherUtterance() async throws {
    let (mailbox, capture, service) = try fixture()
    defer { service.stop(); try? FileManager.default.removeItem(at: mailbox.directory) }
    await service.enable()
    let session = service.state.session
    let base = Date()
    for seconds in [301.0, 3600, 86_400] {
      let now = base.addingTimeInterval(seconds)
      service.tick(now: now)
      XCTAssertEqual(service.state.phase, .ready)
      XCTAssertEqual(service.state.session, session)
      XCTAssertTrue(mailbox.read()?.isLive(at: now) == true)
      XCTAssertEqual(capture.disarmed, 0)
      XCTAssertEqual(capture.starts, 0, "Standby must not start recognition")
    }
    let now = base.addingTimeInterval(86_400)
    let id = UUID()
    try mailbox.send(.init(session: session, request: id, action: .start, createdAt: now))
    service.tick(now: now)
    XCTAssertEqual(capture.starts, 1)
    capture.update?("闲置后仍能输入。", true)
    XCTAssertEqual(service.state.phase, .result)
    service.tick(now: now.addingTimeInterval(3600))
    XCTAssertEqual(service.state.phase, .result)
    XCTAssertEqual(capture.disarmed, 0)
    try mailbox.send(.init(session: session, request: id, action: .acknowledge))
    service.tick()
    XCTAssertEqual(service.state.phase, .ready)
    service.tick(now: now.addingTimeInterval(7200))
    XCTAssertEqual(service.state.phase, .ready)
    XCTAssertEqual(capture.disarmed, 0)
    // Explicit shutdown must still stop the audio engine immediately.
    service.stop()
    XCTAssertEqual(service.state.phase, .stopped)
    XCTAssertEqual(capture.disarmed, 1)
  }

}
