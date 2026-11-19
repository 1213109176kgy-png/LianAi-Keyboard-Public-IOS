import XCTest
import LianAiCore
@testable import LianAiKeyboard

@MainActor
final class KeyboardSetupTests: XCTestCase {
  func testCompletionRequiresCurrentKeyboardReceiptAndPersistsAcrossLaunches() throws {
    let suite = "keyboard.setup.tests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let mailbox = KeyboardSetupMailbox(directory: directory)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
    let setup = KeyboardSetupCoordinator(defaults: defaults, mailbox: mailbox)
    setup.prepare()
    XCTAssertFalse(setup.isComplete)
    // Opening Settings or returning without enabling does not complete anything.
    setup.willOpenSettings()
    XCTAssertTrue(setup.didReturnFromSettings())
    XCTAssertFalse(setup.didReturnFromSettings())
    XCTAssertFalse(setup.isComplete)
    try mailbox.confirmFromKeyboard(hasFullAccess: false)
    setup.checkCompletion()
    XCTAssertFalse(setup.isComplete)
    // A receipt from before a subsequent Settings visit is stale.
    try mailbox.confirmFromKeyboard(hasFullAccess: true)
    setup.willOpenSettings()
    setup.checkCompletion()
    XCTAssertFalse(setup.isComplete)
    try mailbox.confirmFromKeyboard(hasFullAccess: true)
    setup.checkCompletion()
    XCTAssertTrue(setup.isComplete)
    let relaunched = KeyboardSetupCoordinator(defaults: defaults, mailbox: mailbox)
    XCTAssertTrue(relaunched.isComplete)
    // A new installation must not inherit that receipt from a shared container.
    defaults.removePersistentDomain(forName: suite)
    let reinstalled = KeyboardSetupCoordinator(defaults: defaults, mailbox: mailbox)
    reinstalled.prepare()
    XCTAssertFalse(reinstalled.isComplete)
  }
  func testMissingSharedContainerCannotFalselyCompleteSetup() throws {
    let suite = "keyboard.setup.tests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let setup = KeyboardSetupCoordinator(defaults: defaults, mailbox: nil)
    setup.prepare()
    XCTAssertFalse(setup.isComplete)
    XCTAssertFalse(setup.error.isEmpty)
  }
  func testSettingsRoundTripSurvivesProcessRestartWithoutLosingChallenge() throws {
    let suite = "keyboard.setup.tests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let mailbox = KeyboardSetupMailbox(directory: directory)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
    let original = KeyboardSetupCoordinator(defaults: defaults, mailbox: mailbox)
    original.prepare(); original.willOpenSettings()
    let resumed = KeyboardSetupCoordinator(defaults: defaults, mailbox: mailbox)
    resumed.prepare()
    XCTAssertTrue(resumed.didReturnFromSettings())
    XCTAssertFalse(resumed.isComplete)
    try mailbox.confirmFromKeyboard(hasFullAccess: true)
    resumed.checkCompletion()
    XCTAssertTrue(resumed.isComplete)
    XCTAssertFalse(KeyboardSetupCoordinator(defaults: defaults, mailbox: mailbox).waitingForSettings)
  }
}
