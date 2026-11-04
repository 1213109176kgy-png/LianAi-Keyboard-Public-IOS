import LianAiCore
import SwiftUI

struct SubscriptionScreen: View {
  @EnvironmentObject private var store: SharedStore
  @EnvironmentObject private var model: AppModel
  @Environment(\.scenePhase) private var phase
  @StateObject private var purchase = PurchaseCoordinator(store: .shared)
  @State private var plans: [Plan] = []
  @State private var loading = true
  @State private var error = ""
  @State private var alipay = false
  @State private var selected: Plan?
  private var pollIdentity: String {
    "\(store.user?.id ?? ""):\(store.pending?.requestID ?? ""):\(store.pending?.orderID ?? ""):\(phase == .active)"
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      statusCard
      if let pending = store.pending {
        PaymentCard {
          HStack {
            Text(pending.plan.name).font(.system(size: 14, weight: .bold))
            Spacer()
            badge("待确认")
          }
          Hint(purchase.message.isEmpty ? "可继续付款或查询结果，也可直接选择其他套餐。" : purchase.message)
          HStack {
            PaymentButton(title: "继续付款", filled: false, busy: purchase.busy) {
              run { try await purchase.resume() }
            }
            if !pending.orderID.isEmpty {
              PaymentButton(title: "查询结果", filled: false) { Task { await query() } }
            }
          }
        }
      }
      VStack(alignment: .leading, spacing: 6) {
        Text("选择适合你的套餐").font(.system(size: 19, weight: .bold))
        Hint("按需开通，付款确认后生效")
      }.padding(.top, 22).padding(.bottom, 12)
      if loading {
        PaymentCard {
          HStack {
            ProgressView().tint(PaymentStyle.accent)
            Hint("正在加载套餐…")
          }
        }
      } else if plans.isEmpty {
        PaymentCard {
          Hint(error.isEmpty ? "暂无可购买的套餐" : error)
          PaymentButton(title: "重新加载", filled: false) { Task { await load() } }
        }
      } else {
        ForEach(plans) { plan in
          PaymentCard {
            HStack(alignment: .top) {
              VStack(alignment: .leading, spacing: 7) {
                Text(plan.name).font(.system(size: 17, weight: .bold))
              }
              Spacer()
              PaymentPrice(plan: plan, size: 28)
            }
            if !plan.description.isEmpty { Hint(plan.description).lineLimit(2) }
            HStack {
              VStack(alignment: .leading, spacing: 7) {
                Label("\(plan.periodDays) 天有效", systemImage: "clock")
                Label(plan.quota, systemImage: "sparkles")
              }.font(.system(size: 11)).foregroundStyle(LA.muted)
              Spacer()
              PaymentButton(
                title: plan.priceFen == 0 ? "免费领取" : alipay ? "支付宝开通" : "暂未开放",
                filled: plan.priceFen > 0
              ) {
                if store.user == nil {
                  model.notice("请先登录后再购买")
                  model.dialog = .login
                } else {
                  selected = plan
                }
              }.frame(width: 124).disabled(plan.priceFen > 0 && !alipay || purchase.busy)
            }
          }
        }
      }
    }.task(id: store.user?.id) { await load() }
      .task(id: pollIdentity) {
        guard phase == .active, let pending = store.pending, !pending.orderID.isEmpty else {
          return
        }
        for attempt in 0..<80 {
          if attempt > 0 { do { try await Task.sleep(for: .seconds(3)) } catch { return } }
          guard !Task.isCancelled, store.pending?.requestID == pending.requestID else { return }
          await query()
          if store.pending == nil { return }
        }
      }
      .appModal(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }), alignment: .bottom, dim: 0.42) {
        if let plan = selected { confirmation(plan) }
      }
  }
  private var statusCard: some View {
    PaymentCard {
      HStack {
        Icon(name: "wand_sparkles", size: 20).foregroundStyle(PaymentStyle.accent).padding(11).background(
          PaymentStyle.soft, in: RoundedRectangle(cornerRadius: 14))
        VStack(alignment: .leading, spacing: 5) {
          Hint("我的订阅")
          Text(
            model.subscription?.active == true
              ? model.subscription!.planName : store.user == nil ? "登录后开通套餐" : model.subscriptionFailed ? "订阅状态暂未获取" : "还没有生效的套餐"
          ).font(.system(size: 18, weight: .bold))
        }
        Spacer()
        if model.subscription?.active == true { badge("生效中") }
      }
      if let sub = model.subscription, sub.active {
        Divider()
        HStack {
          Hint("剩余 \(sub.daysLeft) 天")
          Spacer()
          Text(sub.dailyQuota == 0 ? "每日不限量" : "每日 \(sub.dailyQuota) 次").font(
            .system(size: 12, weight: .bold)
          ).foregroundStyle(PaymentStyle.accent)
        }
        Hint(
          "到期日期  "
            + Product.dateLabel(milliseconds: sub.expiresAt))
      } else {
        Hint("使用官方 AI 通道，让每次表达更轻松。")
      }
    }
  }
  private func badge(_ title: String) -> some View {
    Text(title).font(.system(size: 11)).foregroundStyle(PaymentStyle.accent).padding(.horizontal, 10).padding(
      .vertical, 5
    ).background(PaymentStyle.soft, in: Capsule())
  }
  private func confirmation(_ plan: Plan) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        VStack(alignment: .leading, spacing: 6) {
          Text(plan.priceFen == 0 ? "确认领取" : "确认开通").font(.system(size: 21, weight: .bold))
          Hint("核对套餐信息后继续")
        }
        Spacer()
        Button {
          selected = nil
        } label: {
          Icon(name: "x").foregroundStyle(LA.muted)
        }
      }
      HStack(spacing: 12) {
        Icon(name: "wand_sparkles", size: 23).foregroundStyle(PaymentStyle.accent)
        VStack(alignment: .leading, spacing: 5) {
          Text(plan.name).font(.system(size: 17, weight: .bold))
          if !plan.description.isEmpty { Hint(plan.description) }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.padding(16).background(PaymentStyle.soft, in: RoundedRectangle(cornerRadius: 18))
      summary("套餐有效期", "\(plan.periodDays) 天")
      summary("每日 AI 额度", plan.dailyQuota == 0 ? "不限次数" : "\(plan.dailyQuota) 次")
      summary(plan.priceFen == 0 ? "领取方式" : "支付方式", plan.priceFen == 0 ? "免费领取" : "支付宝")
      Divider()
      HStack {
        Text(plan.priceFen == 0 ? "本次领取" : "应付金额").font(.system(size: 14, weight: .bold))
        Spacer()
        PaymentPrice(plan: plan, size: 32)
      }
      Hint(plan.priceFen == 0 ? "每个账号每套餐可领取一次。" : "付款确认后自动生效，已有有效期会顺延。")
      PaymentButton(title: plan.priceFen == 0 ? "确认领取" : "确认并支付 \(plan.price)") {
        selected = nil
        run { try await purchase.buy(plan) }
      }
      PaymentButton(title: plan.priceFen == 0 ? "暂不领取" : "暂不开通", filled: false) { selected = nil }
    }
  }
  private func summary(_ title: String, _ value: String) -> some View {
    HStack {
      Hint(title)
      Spacer()
      Text(value).font(.system(size: 14, weight: .semibold))
    }
  }
  private func load() async {
    loading = true
    error = ""
    defer { loading = false }
    do {
      async let result = APIClient.shared.plans()
      async let enabled = APIClient.shared.alipayEnabled()
      plans = try await result
      alipay = (try? await enabled) ?? false
    } catch { self.error = "套餐加载失败，请稍后重试" }
    await model.refreshSubscription()
  }
  private func run(_ action: @escaping @MainActor () async throws -> URL?) {
    Task {
      do {
        if let url = try await action() {
          let opened = await UIApplication.shared.open(url)
          if !opened { model.notice("无法打开支付页面，可以稍后继续付款") }
        } else {
          if !purchase.message.isEmpty { model.notice(purchase.message) }
          await model.refreshSubscription()
        }
      } catch { model.notice(error.localizedDescription) }
    }
  }
  private func query() async {
    do {
      _ = try await purchase.query()
      if store.pending == nil {
        model.notice(purchase.message)
        await model.refreshSubscription()
      }
    } catch is CancellationError {} catch {
      if case ClientError.http(401, _) = error {
        model.notice("登录已过期，请重新登录后查询订单")
      } else {
        model.notice(error.localizedDescription)
      }
    }
  }
}

private enum PaymentStyle {
  static let accent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1, green: 157.0/255, blue: 191.0/255, alpha: 1) : UIColor(red: 219.0/255, green: 52.0/255, blue: 110.0/255, alpha: 1) })
  static let soft = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 68.0/255, green: 43.0/255, blue: 55.0/255, alpha: 1) : UIColor(red: 1, green: 240.0/255, blue: 245.0/255, alpha: 1) })
  static let border = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 99.0/255, green: 65.0/255, blue: 80.0/255, alpha: 1) : UIColor(red: 242.0/255, green: 221.0/255, blue: 230.0/255, alpha: 1) })
}
private struct PaymentCard<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View { Card(padding: 18, radius: 22, border: PaymentStyle.border) { content } }
}
private struct PaymentButton: View {
  var title: String
  var filled = true
  var busy = false
  var action: () -> Void
  var body: some View {
    LAButton(title: title, filled: filled, busy: busy, height: 44, radius: 14, fontSize: 13,
      tint: filled ? Color(hex: 0xFF6B9D) : PaymentStyle.accent, soft: PaymentStyle.soft, action: action)
  }
}
private struct PaymentPrice: View {
  let plan: Plan
  let size: CGFloat
  var body: some View {
    Group {
      if plan.priceFen == 0 { Text("免费").font(.system(size: size, weight: .bold)) }
      else {
        Text("¥").font(.system(size: size * 0.54, weight: .bold)) + Text(String(plan.price.dropFirst())).font(.system(size: size, weight: .bold))
      }
    }.foregroundStyle(PaymentStyle.accent).lineLimit(1)
  }
}
