import XCTest

@testable import LianAiCore

@MainActor
final class MemoryVault: CredentialVault {
  var values: [String: String] = [:]
  func read(key: String) -> String? { values[key] }
  func write(_ value: String, key: String) throws { values[key] = value.isEmpty ? nil : value }
}
actor DelayedTransport: HTTPTransport {
  private var request: URLRequest?
  private var pending: CheckedContinuation<(Data, HTTPURLResponse), any Error>?
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    self.request = request
    return try await withCheckedThrowingContinuation { pending = $0 }
  }
  func waitForRequest() async { while request == nil { await Task.yield() } }
  func respond(_ body: String, status: Int = 200) {
    pending?.resume(
      returning: (
        Data(body.utf8),
        HTTPURLResponse(
          url: request!.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      ))
    pending = nil
  }
}
@MainActor
final class PurchaseRecoveryTests: XCTestCase {
  func testReadOnlySnapshotPrunesExpiredHistoryWithoutSharedWrite() throws {
    let defaults = UserDefaults(suiteName: "LianAiTest-" + UUID().uuidString)!
    let store = SharedStore(defaults: defaults, vault: MemoryVault())
    var settings = Settings()
    settings.retention = "24小时"
    var old = HistoryEntry(kind: "听写", content: "已过保留期")
    old.date = Date().addingTimeInterval(-172800)
    settings.history = [old]
    let data = try JSONEncoder().encode(settings)
    defaults.set(data, forKey: "settings.v1")
    store.reload()
    XCTAssertTrue(store.settings.history.isEmpty)
    XCTAssertEqual(defaults.data(forKey: "settings.v1"), data, "只读键盘加载不能写共享容器")
    store.reload(persistPruned: true)
    let persisted = try JSONDecoder().decode(
      Settings.self, from: defaults.data(forKey: "settings.v1")!)
    XCTAssertTrue(persisted.history.isEmpty, "主 App 恢复时应清除过期记录")
  }
  private func store() throws -> SharedStore {
    let defaults = UserDefaults(suiteName: "LianAiTest-" + UUID().uuidString)!
    let store = SharedStore(defaults: defaults, vault: MemoryVault())
    try store.saveSession(Session(token: "session-a", user: User(id: "user-a")))
    return store
  }
  private var plan: Plan {
    Plan(id: "free", name: "体验", description: "体验", periodDays: 1, priceFen: 0, dailyQuota: 10)
  }
  func testFreeOrderIsConfirmedWithoutOpeningPayment() async throws {
    let store = try store()
    let coordinator = PurchaseCoordinator(
      store: store,
      client: APIClient(transport: FixtureTransport("{\"status\":\"created\",\"free\":true}")))
    let url = try await coordinator.buy(plan)
    XCTAssertNil(url)
    XCTAssertNil(store.pending)
    XCTAssertEqual(coordinator.message, "支付成功，套餐已开通")
  }
  func testLateNotFoundCannotEraseNewPendingPurchase() async throws {
    let store = try store()
    let transport = DelayedTransport()
    let coordinator = PurchaseCoordinator(store: store, client: APIClient(transport: transport))
    var old = PendingPurchase(userID: "user-a", plan: plan)
    old.orderID = "old-order"
    store.pending = old
    let query = Task { try await coordinator.query() }
    await transport.waitForRequest()
    let replacement = PendingPurchase(userID: "user-a", plan: plan)
    store.pending = replacement
    await transport.respond("{\"message\":\"订单不存在\"}", status: 404)
    do {
      _ = try await query.value
      XCTFail("Expected HTTP error")
    } catch {}
    XCTAssertEqual(store.pending?.requestID, replacement.requestID)
  }
  func testLatePaidResponseCannotSettleAnotherLoginSession() async throws {
    let store = try store()
    let transport = DelayedTransport()
    let coordinator = PurchaseCoordinator(store: store, client: APIClient(transport: transport))
    var old = PendingPurchase(userID: "user-a", plan: plan)
    old.orderID = "old-order"
    store.pending = old
    let query = Task { try await coordinator.query() }
    await transport.waitForRequest()
    try store.saveSession(Session(token: "session-b", user: User(id: "user-a")))
    let replacement = PendingPurchase(userID: "user-a", plan: plan)
    store.pending = replacement
    await transport.respond("{\"status\":\"paid\"}")
    do {
      _ = try await query.value
      XCTFail("Expected stale session error")
    } catch {}
    XCTAssertEqual(store.pending?.requestID, replacement.requestID)
    XCTAssertTrue(coordinator.message.isEmpty)
  }
  func testChangingAccountClearsPreparedResultAndPendingOrder() throws {
    let store = try store()
    store.prepared = PreparedResult(userID: "user-a", kind: "听写", text: "测试")
    store.pending = PendingPurchase(userID: "user-a", plan: plan)
    try store.saveSession(Session(token: "session-b", user: User(id: "user-b")))
    XCTAssertNil(store.prepared)
    XCTAssertNil(store.pending)
  }
}
