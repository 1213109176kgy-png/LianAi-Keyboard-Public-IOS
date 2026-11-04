import LianAiCore
import SwiftUI

enum Page: String, CaseIterable {
  case home, test, profile, subscription, settings, layout, effects, auxiliary, management, models,
    optimize, clipboard, data, permissions, guide, about
  var title: String {
    switch self {
    case .home: "首页"
    case .test: "键盘试用"
    case .profile: "个人中心"
    case .subscription: "订阅套餐"
    case .settings: "设置"
    case .layout: "布局和显示"
    case .effects: "按键效果"
    case .auxiliary: "辅助输入"
    case .management: "键盘管理"
    case .models: "大模型配置"
    case .optimize: "优化输入"
    case .clipboard: "剪贴板"
    case .data: "本机数据"
    case .permissions: "权限管理"
    case .guide: "使用指引"
    case .about: "关于我们"
    }
  }
}
enum Dialog: String, Identifiable {
  case login, logout, feedback, privacy, version, setup, microphone, voice
  var id: String { rawValue }
}
@MainActor
final class AppModel: ObservableObject {
  @Published var page: Page = .home
  @Published var dialog: Dialog?
  @Published var toast = ""
  @Published var subscription: Subscription?
  @Published var subscriptionFailed = false
  private var cloudReturnPage: Page = .settings
  func navigate(_ next: Page) {
    if next == .models { cloudReturnPage = page == .home ? .home : .settings }
    withAnimation(.easeOut(duration: 0.2)) { page = next }
  }
  func back() {
    let parent: Page
    switch page {
    case .home, .profile, .test: parent = .home
    case .subscription, .settings, .about, .guide: parent = .profile
    case .models: parent = cloudReturnPage
    default: parent = .settings
    }
    withAnimation(.easeOut(duration: 0.2)) { page = parent }
  }
  func tab(_ next: Page) {
    page = next
  }
  func notice(_ text: String) { toast = text }
  func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }
  func refreshSubscription() async {
    let store = SharedStore.shared
    guard let token = store.token() else {
      subscription = nil
      subscriptionFailed = false
      return
    }
    let user = store.user?.id
    do {
      let value = try await APIClient.shared.subscription(token: token)
      guard user == store.user?.id, store.token() == token else { return }
      subscription = value
      subscriptionFailed = false
    } catch {
      guard user == store.user?.id, store.token() == token else { return }
      subscription = nil
      subscriptionFailed = true
    }
  }
  func handle(_ url: URL) {
    UserDefaults(suiteName: Product.group)?.removeObject(forKey: "requestedDestination")
    if PaymentPolicy.isReturn(url) {
      tab(.profile)
      navigate(.subscription)
    } else if url.scheme == "lianai", url.host == "voice" {
      dialog = .voice
    } else if url.scheme == "lianai", url.host == "setup" {
      dialog = .setup
    } else if url.scheme == "lianai", url.host == "models" {
      navigate(.models)
    } else if url.scheme == "lianai", url.host == "subscription" {
      navigate(.subscription)
    }
  }
  func resumeKeyboardRequest() {
    let defaults = UserDefaults(suiteName: Product.group)
    guard let destination = defaults?.string(forKey: "requestedDestination"),
      ["voice", "models", "subscription", "setup"].contains(destination),
      let url = URL(string: "lianai://" + destination)
    else { return }
    handle(url)
  }
}
@main
struct LianAiApp: App {
  @StateObject private var store = SharedStore.shared
  @StateObject private var model = AppModel()
  var body: some Scene {
    WindowGroup {
      RootView().environmentObject(store).environmentObject(model).preferredColorScheme(
        store.settings.theme == "自适应系统" ? nil : store.settings.theme == "暗黑模式" ? .dark : .light
      ).onOpenURL { model.handle($0) }
    }
  }
}
