import XCTest
@testable import LianAiCore

private actor SessionRequestRecorder: HTTPTransport {
  private var requests = 0
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests += 1
    throw ClientError.message("Unexpected authenticated request")
  }
  func count() -> Int { requests }
}

@MainActor
final class SessionConsistencyTests: XCTestCase {
  func testReinstallWithSurvivingKeychainTokenCannotCallOfficialAI() async throws {
    let suite = "session.reinstall.tests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let vault = MemoryVault()
    let previous = SharedStore(defaults: defaults, vault: vault)
    try previous.saveSession(Session(token: "previous-install-session", user: User(id: "previous-user")))
    // Reinstallation removes app data without promising to remove Keychain items.
    defaults.removePersistentDomain(forName: suite)
    let reinstalled = SharedStore(defaults: defaults, vault: vault)
    XCTAssertNil(reinstalled.user)
    XCTAssertEqual(vault.read(key: "token"), "previous-install-session")
    XCTAssertNil(reinstalled.token(), "未登录界面不能使用旧安装留下的官方登录凭据")
    let recorder = SessionRequestRecorder()
    do {
      _ = try await APIClient(transport: recorder).suggestions(
        text: "测试", relation: nil, settings: Settings(), key: nil, token: reinstalled.token())
      XCTFail("Expected login/subscription or model configuration guide")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("请开通 VIP"), error.localizedDescription)
    }
    let count = await recorder.count()
    XCTAssertEqual(count, 0, "不能向官方代理发送残留 token 或未经授权的 AI 请求")
  }

  func testValidLoginSurvivesRelaunchAndLogoutRemovesAccess() throws {
    let suite = "session.lifecycle.tests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let vault = MemoryVault()
    let app = SharedStore(defaults: defaults, vault: vault)
    try app.saveSession(Session(token: "current-session", user: User(id: "current-user")))
    let keyboard = SharedStore(defaults: defaults, vault: vault)
    XCTAssertEqual(keyboard.token(), "current-session")
    XCTAssertEqual(keyboard.user?.id, "current-user")
    try app.logout()
    // Even before the keyboard reloads its account view, the credential is gone.
    XCTAssertNil(keyboard.token())
    keyboard.reloadUser()
    XCTAssertNil(keyboard.user)
  }

  func testMissingOrEmptyCredentialDoesNotAuthenticateVisibleAccount() throws {
    let suite = "session.credential.tests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let vault = MemoryVault()
    let store = SharedStore(defaults: defaults, vault: vault)
    try store.saveSession(Session(token: "current-session", user: User(id: "current-user")))
    vault.values.removeValue(forKey: "token")
    XCTAssertNil(store.token())
    vault.values["token"] = ""
    XCTAssertNil(store.token())
  }
}
