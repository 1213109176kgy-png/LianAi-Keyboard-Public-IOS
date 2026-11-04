import Combine
import Foundation

@MainActor
public final class PurchaseCoordinator: ObservableObject {
  @Published public private(set) var busy = false
  @Published public private(set) var message = ""
  private let store: SharedStore
  private let client: APIClient
  public init(store: SharedStore, client: APIClient = .shared) {
    self.store = store
    self.client = client
  }
  private func identity() throws -> (String, String) {
    guard let id = store.user?.id, let token = store.token() else {
      throw ClientError.message("请先登录后再购买")
    }
    return (id, token)
  }
  private func requireIdentity(_ id: String, _ token: String) throws {
    guard store.user?.id == id && store.token() == token else {
      throw ClientError.message("登录账号已切换，请重新查询")
    }
  }
  public func buy(_ plan: Plan, retry: Bool = false) async throws -> URL? {
    guard !busy else { return nil }
    let (id, token) = try identity()
    busy = true
    defer { busy = false }
    let pending =
      retry
      ? store.pending ?? PendingPurchase(userID: id, plan: plan)
      : PendingPurchase(userID: id, plan: plan)
    store.pending = pending
    do {
      let order = try await client.createOrder(
        planID: pending.plan.id, requestID: pending.requestID, token: token)
      try requireIdentity(id, token)
      if order.free == true || PaymentPolicy.terminal(order.status) {
        settle(order.free == true ? "paid" : order.status)
        return nil
      }
      guard let orderID = order.orderId, !orderID.isEmpty else {
        throw ClientError.message("服务未返回订单号，请稍后重试")
      }
      var saved = pending
      saved.orderID = orderID
      saved.payURL = order.payUrl ?? ""
      store.pending = saved
      return try PaymentPolicy.validatedPaymentURL(saved.payURL)
    } catch {
      if store.user?.id == id, store.token() == token,
        store.pending?.requestID == pending.requestID,
        case ClientError.http(let code, _) = error,
        (400..<500).contains(code)
      {
        store.pending = nil
      }
      throw error
    }
  }
  private func settle(_ status: String) {
    store.pending = nil
    message =
      status == "paid"
      ? "支付成功，套餐已开通" : status == "closed" ? "订单已关闭，可重新购买" : "订单已超时，可重新购买；若已付款，请联系管理员核实"
  }
  public func query() async throws -> Order? {
    guard let pending = store.pending, !pending.orderID.isEmpty else { return nil }
    let (id, token) = try identity()
    do {
      let result = try await client.order(id: pending.orderID, token: token)
      try requireIdentity(id, token)
      guard store.pending?.requestID == pending.requestID else { return nil }
      if PaymentPolicy.terminal(result.status) {
        settle(result.status)
      } else {
        message = "尚未确认付款。已付款请稍候，也可点击「查询结果」。"
      }
      return result
    } catch {
      if store.user?.id == id, store.token() == token,
        store.pending?.requestID == pending.requestID,
        case ClientError.http(404, _) = error
      {
        store.pending = nil
      }
      throw error
    }
  }
  public func resume() async throws -> URL? {
    guard let pending = store.pending else { return nil }
    if pending.orderID.isEmpty { return try await buy(pending.plan, retry: true) }
    guard let result = try await query(), !PaymentPolicy.terminal(result.status),
      let url = result.payUrl
    else { return nil }
    return try PaymentPolicy.validatedPaymentURL(url)
  }
}
