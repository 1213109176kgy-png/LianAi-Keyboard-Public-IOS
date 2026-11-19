import LianAiCore
import SwiftUI

struct RootView: View {
  @EnvironmentObject private var store: SharedStore
  @EnvironmentObject private var model: AppModel
  @Environment(\.scenePhase) private var scenePhase
  @State private var splash = true
  @State private var scrollPositions: [Page: ScrollPosition] = [:]
  var body: some View {
    let displayedPage = model.page
    ZStack {
      LA.background.ignoresSafeArea()
      VStack(spacing: 0) {
        if model.page == .knowledge {
          KnowledgeScreen().frame(maxWidth: 560, maxHeight: .infinity).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ScrollView {
            VStack(spacing: 0) {
              if model.page != .home { header }
              pageContent
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 28).frame(
              maxWidth: 560
            ).frame(maxWidth: .infinity)
          }.scrollPosition(Binding(
            get: { scrollPositions[displayedPage] ?? ScrollPosition(y: 0) },
            set: { scrollPositions[displayedPage] = $0 }
          )).id(model.page).scrollDismissesKeyboard(.interactively)
        }
        if !model.knowledgeDetail { bottomBar }
      }.ignoresSafeArea(.keyboard, edges: model.page == .knowledge ? [] : .bottom)
      if model.dialog != nil && model.dialog != .setup {
        Color.black.opacity(0.34).ignoresSafeArea().onTapGesture { model.dialog = nil }
        dialogContent.padding(.horizontal, 26).frame(maxWidth: 460)
      }
      if !model.toast.isEmpty {
        VStack {
          Spacer()
          Text(model.toast).font(.system(size: 13)).foregroundStyle(.white).padding(14).background(
            .black.opacity(0.8), in: RoundedRectangle(cornerRadius: 14)
          ).padding(.horizontal, 24).padding(.bottom, 90)
        }.allowsHitTesting(false).task(id: model.toast) {
          try? await Task.sleep(for: .seconds(3))
          if !Task.isCancelled { model.toast = "" }
        }
      }
      if splash {
        GeometryReader { g in
          Image("splash").resizable().scaledToFill().frame(
            width: g.size.width, height: g.size.height
          ).clipped()
        }.ignoresSafeArea().task {
          try? await Task.sleep(for: .seconds(1.8))
          withAnimation { splash = false }
        }
      }
    }.foregroundStyle(LA.ink)
      .sheet(isPresented: Binding(
        get: { model.dialog == .setup },
        set: { if !$0 && model.dialog == .setup { model.dialog = nil } }
      )) { KeyboardSetupScreen(setup: model.keyboardSetup) }
      .task {
        KeyboardUITestSupport.bootstrap()
        await KeyboardVoiceUITestSupport.bootstrap()
        if let raw = ProcessInfo.processInfo.environment["LIANAI_PREVIEW_PAGE"],
          let p = Page(rawValue: raw)
        {
          model.page = p
          splash = false
        }
        model.resumeKeyboardRequest()
        model.presentInitialKeyboardSetup()
        await model.refreshSubscription()
      }
      .onChange(of: store.user?.id) { _, _ in
        KeyboardVoiceService.shared.stop(message: "账号已变更，请重新开启语音会话")
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active {
          store.reload(persistPruned: true)
          model.resumeKeyboardRequest()
          model.keyboardSetup.checkCompletion()
          Task { await model.refreshSubscription() }
        }
      }
  }
  private var headerHeight: CGFloat {
    switch model.page { case .profile: 44; case .subscription: 52; case .models, .settings: 58; default: 64 }
  }
  private var backWidth: CGFloat { model.page == .subscription ? 44 : [.models, .settings].contains(model.page) ? 48 : 52 }
  private var header: some View {
    HStack {
      if model.page != .profile {
        Button {
          model.back()
        } label: {
          Icon(name: "chevron_left").foregroundStyle(LA.ink).frame(width: backWidth, height: headerHeight)
        }.accessibilityLabel("返回")
      } else {
        Color.clear.frame(width: backWidth, height: headerHeight)
      }
      Spacer()
      Text(model.page.title).font(.system(size: model.page == .subscription ? 18 : 14, weight: .bold))
      Spacer()
      Color.clear.frame(width: backWidth, height: headerHeight)
    }
  }
  private var bottomBar: some View {
    HStack(spacing: 8) {
      tab("house", "首页", .home)
      tab("keyboard", "键盘", .test)
      tab("book_open", "知识库", .knowledge)
      tab("user_round", "我的", .profile)
    }.padding(.horizontal, 10).padding(.vertical, 7).background(LA.panel).overlay(alignment: .top) {
      Rectangle().fill(LA.key).frame(height: 1)
    }
  }
  private func tab(_ icon: String, _ label: String, _ page: Page) -> some View {
    let selected =
      model.page == page || (page == .profile && ![.home, .test, .knowledge].contains(model.page))
    return Button {
      model.tab(page)
    } label: {
      VStack(spacing: 0) {
        Icon(name: icon, size: 22).frame(height: 28)
        Text(label).font(.system(size: 12, weight: selected ? .bold : .regular)).frame(height: 22)
      }.frame(maxWidth: .infinity).frame(height: 58).foregroundStyle(
        selected ? LA.accent : LA.muted
      ).background(selected ? LA.key : .clear, in: RoundedRectangle(cornerRadius: 16))
    }.buttonStyle(.plain)
  }
  @ViewBuilder private var pageContent: some View {
    switch model.page {
    case .home: HomeScreen()
    case .profile: ProfileScreen()
    case .test: TrialScreen()
    case .settings: SettingsHub()
    case .models: ModelScreen()
    case .subscription: SubscriptionScreen()
    case .layout, .effects, .auxiliary, .management, .clipboard:
      KeyboardSettingsScreen(page: model.page)
    case .optimize: OptimizeScreen()
    case .data: LocalDataScreen()
    case .permissions: PermissionScreen()
    case .guide: GuideScreen()
    case .about: AboutScreen()
    case .knowledge: KnowledgeScreen()
    }
  }
  @ViewBuilder private var dialogContent: some View {
    switch model.dialog {
    case .login: LoginDialog()
    case .changePassword: ChangePasswordDialog()
    case .logout:
      DialogCard(title: "退出登录？", subtitle: "本机登录状态将被清除") {
        Hint("订阅权益不受影响，下次购买前重新登录即可。")
        LAButton(title: "退出登录") {
          let token = store.token()
          do {
            try store.logout()
            model.subscription = nil
            model.dialog = nil
            model.notice("已退出登录")
            if let token { Task { try? await APIClient.shared.logout(token: token) } }
          } catch { model.notice(error.localizedDescription) }
        }
        LAButton(title: "取消", filled: false) { model.dialog = nil }
      }
    case .feedback:
      DialogCard(title: "意见反馈", subtitle: "扫码添加微信，直接反馈问题和建议") {
        Image("developer").resizable().scaledToFit().frame(maxHeight: 240)
        Hint("扫一扫上方二维码，添加开发者微信\n使用体验、问题和建议都欢迎")
      }
    case .privacy:
      DialogCard(title: "隐私政策", subtitle: "恋爱键盘如何处理你的数据") {
        ScrollView {
          Hint(
            "基础拼音、候选与学习在本机运行。只有你主动使用 AI 时，相关文本、截图或音频才发送给你选择的服务商或官方代理。知识库保存在本机，主动使用 AI 时，所选且启用的知识库会提供相关片段作为参考。官方通道使用账号验证，自配模型密钥保存在 Keychain。输入历史和剪贴板历史默认关闭，可在设置中清除。开启完全访问允许键盘联网，并不表示日常按键会上传。键盘语音会话需主动开启，期间系统显示麦克风指示灯；待机音频立即丢弃，仅语音输入期间进行识别，优先本机识别，不支持时使用 Apple 语音服务。请勿发送无关私人信息。"
          )
        }.frame(maxHeight: 280)
      }
    case .version:
      DialogCard(title: "版本信息", subtitle: "当前版本 \(model.versionLabel) · iOS") {
        Hint("前往 App Store 查看新版本，并在应用详情页完成更新。")
        LAButton(title: model.openingAppStore ? "正在打开 App Store…" : "前往 App Store 升级") {
          model.openAppStore()
        }.disabled(model.openingAppStore)
      }
    case .setup:
      EmptyView() // Presented as a scrollable sheet so the verification keyboard fits.
    case .microphone:
      DialogCard(title: "开启麦克风权限", subtitle: "语音输入必需") {
        Hint("首次开启语音会话后，返回聊天长按空格即可直接语音输入；会话结束后需重新开启。")
        LAButton(title: "开始语音输入") { model.dialog = .voice }
      }
    case .voice: KeyboardVoiceSetupView()
    case nil: EmptyView()
    }
  }
}
struct DialogCard<Content: View>: View {
  @EnvironmentObject private var model: AppModel
  let title: String
  var subtitle = ""
  @ViewBuilder var content: Content
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text(title).font(.system(size: 17, weight: .bold))
          if !subtitle.isEmpty { Text(subtitle).font(.system(size: 12)) }
        }
        Spacer()
        Button {
          model.dialog = nil
        } label: {
          Icon(name: "x", size: 22).frame(width: 36, height: 36)
        }.accessibilityLabel("关闭")
      }.foregroundStyle(.white).padding(20).background(LA.gradient)
      VStack(alignment: .leading, spacing: 12) { content }.padding(20).frame(maxWidth: .infinity)
        .background(LA.panel)
    }.clipShape(RoundedRectangle(cornerRadius: 22)).shadow(color: .black.opacity(0.14), radius: 20)
  }
}
