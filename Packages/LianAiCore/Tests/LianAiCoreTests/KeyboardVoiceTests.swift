import Foundation
import XCTest
@testable import LianAiCore

final class KeyboardVoiceTests: XCTestCase {
  func testQuickReleaseDoesNotOverwriteStartAndCancellationRemainsOrdered() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let mailbox = try KeyboardVoiceMailbox(directory: directory)
    let session = UUID(), request = UUID(), now = Date()
    for (index, action) in [KeyboardVoiceCommand.Action.start, .finish, .cancel].enumerated() {
      try mailbox.send(KeyboardVoiceCommand(session: session, request: request, action: action,
        createdAt: now.addingTimeInterval(Double(index) * 0.01)))
    }
    let commands = try mailbox.commands()
    XCTAssertEqual(commands.map(\.action), [.start, .finish, .cancel])
    XCTAssertEqual(Set(commands.map(\.request)), [request])
    for command in commands { mailbox.remove(command) }
    XCTAssertTrue(try mailbox.commands().isEmpty)
    let state = KeyboardVoiceState(session: session, request: request, phase: .result, text: "明天见")
    try mailbox.write(state); XCTAssertEqual(mailbox.read(), state)
    try mailbox.write(KeyboardVoiceState(session: session, phase: .ready))
    XCTAssertEqual(mailbox.read()?.text, "", "Acknowledgement must erase shared transcript")
  }
  func testHeartbeatExpiryAndClockSkewDoNotReportDeadSessionAsLive() {
    let now = Date()
    let ready = KeyboardVoiceState(phase: .ready, updatedAt: now)
    XCTAssertTrue(ready.isLive(at: now.addingTimeInterval(3)))
    XCTAssertFalse(ready.isLive(at: now.addingTimeInterval(4)))
    XCTAssertFalse(ready.isLive(at: now.addingTimeInterval(-3)))
    XCTAssertFalse(KeyboardVoiceState(phase: .stopped).isLive())
  }
  func testDeliveryAnchorRejectsNewFieldCaretSelectionAccountOrDraft() {
    let base = VoiceInsertionAnchor(document: UUID(), before: "你", after: "好", selected: nil,
      mode: "超会说", draft: "原草稿", cursor: 3, account: "A")
    var changed = base; changed.document = UUID(); XCTAssertNotEqual(changed, base)
    changed = base; changed.before = "你好"; XCTAssertNotEqual(changed, base)
    changed = base; changed.after = ""; XCTAssertNotEqual(changed, base)
    changed = base; changed.selected = "好"; XCTAssertNotEqual(changed, base)
    changed = base; changed.account = "B"; XCTAssertNotEqual(changed, base)
    changed = base; changed.mode = "键盘"; XCTAssertNotEqual(changed, base)
    changed = base; changed.cursor = 0; XCTAssertNotEqual(changed, base)
    changed = base; changed.draft = "已修改"; XCTAssertNotEqual(changed, base)
  }
  @MainActor
  func testVoiceAccountRefreshSeesOtherProcessLoginAndLogoutWithoutReplacingActiveSettings() throws {
    let name = "LianAiVoice-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let vault = MemoryVault()
    let app = SharedStore(defaults: defaults, vault: vault)
    let keyboard = SharedStore(defaults: defaults, vault: vault)
    keyboard.settings.theme = "暗黑模式"
    app.settings.theme = "亮色模式"
    let settingsData = defaults.data(forKey: "settings.v1")
    try app.saveSession(Session(token: "a", user: User(id: "A")))
    keyboard.reloadUser(); XCTAssertEqual(keyboard.user?.id, "A")
    try app.saveSession(Session(token: "b", user: User(id: "B")))
    keyboard.reloadUser(); XCTAssertEqual(keyboard.user?.id, "B")
    try app.logout(); keyboard.reloadUser(); XCTAssertNil(keyboard.user)
    XCTAssertEqual(keyboard.settings.theme, "暗黑模式", "Voice polling must retain the active keyboard settings snapshot")
    XCTAssertEqual(defaults.data(forKey: "settings.v1"), settingsData, "Account polling must never rewrite shared settings")
  }

}
