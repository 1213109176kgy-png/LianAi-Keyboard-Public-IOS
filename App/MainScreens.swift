import LianAiCore
import SwiftUI

struct HomeScreen: View {
  @EnvironmentObject private var model: AppModel
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image("brand").resizable().frame(width: 38, height: 38).clipShape(
          RoundedRectangle(cornerRadius: 12))
        Text("恋爱键盘").font(.system(size: 14, weight: .bold))
      }.frame(maxWidth: .infinity).padding(.top, 6).padding(.bottom, 6)
      VStack(alignment: .leading, spacing: 8) {
        Text("让聊天更有爱 💕").font(.system(size: 14, weight: .bold))
        Text("AI助你成为恋爱高手，每一句话都充满魅力").font(.system(size: 12))
      }.foregroundStyle(.white).padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(LA.gradient, in: RoundedRectangle(cornerRadius: 24))
      SectionLabel("核心功能")
      feature("message_circle_more", "AI智能回复", "粘贴对方消息，一键生成高情商回复", LA.accent)
      feature("wand_sparkles", "话术优化", "把你想说的话润色优化，表达更有魅力", LA.orange)
      feature("zap", "情感分析", "AI读懂TA的情绪和暗示，回复不再尴尬", Color(hex: 0xE75480))
      SectionLabel("如何使用 · 4步快速上手")
      Card(spacing: 0) {
        step("1", "启用恋爱键盘", "进入系统键盘设置并启用") { model.dialog = .setup }
        Divider()
        step("2", "切换输入法", "在输入框中长按地球键选择恋爱键盘") { model.dialog = .setup }
        Divider()
        step("3", "配置AI大模型", "购买套餐免配置，或填自己的模型接口") { model.navigate(.models) }
        Divider()
        step("4", "开始使用", "进入键盘栏目，点击试用弹出输入法") { model.tab(.test) }
      }
    }
  }
  private func feature(_ icon: String, _ title: String, _ detail: String, _ color: Color)
    -> some View
  {
    HStack(spacing: 14) {
        Icon(name: icon, size: 28).foregroundStyle(color).frame(width: 52, height: 52).background(
          color.opacity(0.11), in: Circle())
        VStack(alignment: .leading, spacing: 4) {
          Text(title).font(.system(size: 14, weight: .bold))
          Text(detail).font(.system(size: 12)).foregroundStyle(LA.muted)
        }
        Spacer(minLength: 0)
      }.padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 14)
        .background(LA.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(LA.key, lineWidth: 1))
  }
  private func step(_ n: String, _ title: String, _ detail: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      HStack(spacing: 12) {
        Text(n).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).frame(
          width: 34, height: 34
        ).background(LA.accent, in: Circle())
        VStack(alignment: .leading, spacing: 5) {
          Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(LA.ink)
          Text(detail).font(.system(size: 12)).foregroundStyle(LA.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
        Icon(name: "chevron_right", size: 20).foregroundStyle(LA.accent).frame(width: 28)
      }.frame(minHeight: 70).contentShape(Rectangle())
    }.buttonStyle(.plain)
  }
}
struct ProfileScreen: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var store: SharedStore
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Button {
        model.dialog = store.user == nil ? .login : .logout
      } label: {
        HStack(spacing: 14) {
          Image("brand").resizable().padding(9).frame(width: 66, height: 66).background(.white).clipShape(
            RoundedRectangle(cornerRadius: 18))
          VStack(alignment: .leading, spacing: 6) {
            Text(store.user?.displayPhone ?? "未登录").font(.system(size: 14, weight: .bold))
            Text(subtitle).font(.system(size: 12))
          }.frame(maxWidth: .infinity, alignment: .leading)
          Icon(name: "chevron_right", size: 20)
        }.foregroundStyle(.white).padding(20).background(
          LA.gradient, in: RoundedRectangle(cornerRadius: 24))
      }.buttonStyle(.plain)
      if store.user != nil {
        SectionLabel("账号设置")
        Card(spacing: 0) {
          ActionRow(title: "修改密码", detail: "验证旧密码后设置新密码", icon: "shield_check") {
            model.dialog = .changePassword
          }.accessibilityIdentifier("changePasswordEntry")
        }
      }
      SectionLabel("订阅")
      Card(spacing: 0) {
        ActionRow(title: "订阅套餐", detail: store.user == nil ? "购买套餐需先登录" : "查看套餐与订阅状态", icon: "zap")
        { model.navigate(.subscription) }
      }
      SectionLabel("功能与设置")
      Card(spacing: 0) {
        ActionRow(title: "设置", detail: "键盘、AI、数据与权限", icon: "sliders_horizontal") {
          model.navigate(.settings)
        }
        Divider()
        ActionRow(title: "键盘效果预览", detail: "进入试用页体验完整键盘", icon: "keyboard") { model.tab(.test) }
        Divider()
        ActionRow(title: "使用指引", detail: "查看键盘与 AI 功能说明", icon: "book_open") {
          model.navigate(.guide)
        }
      }
      SectionLabel("支持")
      Card(spacing: 0) {
        ActionRow(title: "意见反馈", detail: "扫码添加微信，反馈问题与建议", icon: "message_circle_more") {
          model.dialog = .feedback
        }
        Divider()
        ActionRow(title: "关于我们", detail: "开发者、微信与随缘打赏", icon: "house") { model.navigate(.about) }
        Divider()
        ActionRow(title: "检查更新", detail: "当前版本 1.5.9", icon: "history") { model.dialog = .version }
      }
    }.task { await model.refreshSubscription() }
  }
  private var subtitle: String {
    guard store.user != nil else { return "点击登录或注册" }
    guard let sub = model.subscription, sub.active else { return "未购买套餐" }
    return
      "\(sub.planName) · \(Product.dateLabel(milliseconds: sub.expiresAt)) 到期"
  }
}
struct TrialScreen: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.scenePhase) private var phase
  @State private var text = ""
  @FocusState private var focused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionLabel("体验输入")
      Card {
        ZStack(alignment: .topLeading) {
          if text.isEmpty {
            Text("在这里试试拼音、英文、语音和润色").font(.system(size: 14)).foregroundStyle(LA.muted).padding(
              .top, 12
            ).padding(.leading, 6).allowsHitTesting(false)
          }
          TextEditor(text: $text).font(.system(size: 14)).frame(height: 190)
            .scrollContentBackground(.hidden).focused($focused).accessibilityIdentifier(
              "trialInput")
        }.padding(10).background(LA.key, in: RoundedRectangle(cornerRadius: 16))
        LAButton(title: "试用键盘") {
          focused = false
          Task {
            try? await Task.sleep(for: .milliseconds(80))
            focused = true
          }
        }
        LAButton(title: "清空文本", filled: false) { text = "" }
      }
      Hint("长按系统键盘上的地球键，选择「恋爱键盘」。尚未启用时，请先到系统键盘设置添加。")
    }.onChange(of: phase) { _, phase in if phase != .active { focused = false } }
  }
}
struct SettingsHub: View {
  @EnvironmentObject private var model: AppModel
  private let groups: [(String, [(Page, String, String)])] = [
    (
      "键盘设置",
      [
        (.layout, "主题与候选词", "layout_dashboard"), (.effects, "声音与触感", "zap"),
        (.auxiliary, "标点与英文", "sliders_horizontal"), (.management, "布局与模式", "keyboard"),
      ]
    ),
    (
      "AI 与数据",
      [
        (.models, "套餐或自定义接口", "cloud"), (.optimize, "词典与文风", "wand_sparkles"),
        (.clipboard, "本机历史", "clipboard_list"), (.data, "历史与学习", "history"),
      ]
    ), ("其他", [(.permissions, "输入法、录音与悬浮窗", "shield_check"), (.about, "开发者与使用指引", "circle_help")]),
  ]
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(groups, id: \.0) { group in
        SectionLabel(group.0)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
          ForEach(group.1, id: \.0) { page, detail, icon in
            Button {
              model.navigate(page)
            } label: {
              VStack(alignment: .leading, spacing: 0) {
                HStack {
                  Icon(name: icon, size: 22).foregroundStyle(LA.accent).frame(width: 36, height: 36)
                    .background(LA.accent.opacity(0.15), in: Circle())
                  Spacer()
                  Icon(name: "chevron_right", size: 18).foregroundStyle(LA.muted)
                }.frame(height: 34)
                Text(page == .about ? "关于与帮助" : page.title)
                  .font(.system(size: 14, weight: .bold)).foregroundStyle(LA.ink).padding(.top, 8)
                Text(detail).font(.system(size: 12)).foregroundStyle(LA.muted).lineLimit(2).padding(.top, 4)
                Spacer(minLength: 0)
              }.padding(.leading, 13).padding(.trailing, 12).padding(.top, 11).padding(.bottom, 10)
                .frame(maxWidth: .infinity).frame(height: 120)
                .background(LA.panel, in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(.plain)
          }
        }
      }
    }
  }
}
struct LoginDialog: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var store: SharedStore
  @State private var phone = ""
  @State private var password = ""
  @State private var register = false
  @State private var busy = false
  @State private var error = ""
  var body: some View {
    DialogCard(
      title: register ? "注册账号" : "登录账号", subtitle: register ? "注册成功后将自动登录，无需再次输入" : "购买订阅套餐前需要先登录"
    ) {
      Field(title: "手机号", text: $phone).keyboardType(.phonePad)
      Field(title: "密码（8~64 位）", text: $password, secure: true)
      if !error.isEmpty { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
      LAButton(title: register ? "注册并登录" : "登录", busy: busy) { Task { await submit() } }
      Button(register ? "已有账号？直接登录" : "还没有账号？免费注册") {
        register.toggle()
        error = ""
      }.font(.system(size: 13)).foregroundStyle(LA.accent).frame(maxWidth: .infinity).padding(
        .top, 4
      ).disabled(busy)
    }
  }
  private func submit() async {
    busy = true
    defer { busy = false }
    do {
      let session = try await APIClient.shared.login(
        phone: phone.trimmingCharacters(in: .whitespaces), password: password, register: register)
      try store.saveSession(session)
      model.dialog = nil
      model.notice("已登录 \(session.user.displayPhone)")
      await model.refreshSubscription()
    } catch { self.error = error.localizedDescription }
  }
}

struct ChangePasswordDialog: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var store: SharedStore
  @State private var oldPassword = ""
  @State private var newPassword = ""
  @State private var confirmation = ""
  @State private var busy = false
  @State private var error = ""
  var body: some View {
    DialogCard(title: "修改密码", subtitle: "修改后，其他登录会话需要重新登录") {
      Field(title: "旧密码", text: $oldPassword, secure: true)
        .textContentType(.password).accessibilityIdentifier("oldPassword")
      Field(title: "新密码（8～64 位）", text: $newPassword, secure: true)
        .textContentType(.newPassword).accessibilityIdentifier("newPassword")
      Field(title: "再次输入新密码", text: $confirmation, secure: true)
        .textContentType(.newPassword).accessibilityIdentifier("confirmPassword")
      if !error.isEmpty {
        Text(error).font(.system(size: 12)).foregroundStyle(.red)
          .accessibilityIdentifier("changePasswordError")
      }
      LAButton(title: busy ? "正在修改…" : "确认修改", busy: busy) {
        Task { await submit() }
      }.accessibilityIdentifier("changePasswordSubmit")
    }
  }
  private func submit() async {
    guard !busy else { return }
    guard newPassword == confirmation else {
      error = "两次输入的新密码不一致"
      return
    }
    guard let token = store.token() else {
      error = "请先登录"
      return
    }
    error = ""
    busy = true
    defer { busy = false }
    do {
      try await APIClient.shared.changePassword(
        token: token, oldPassword: oldPassword, newPassword: newPassword)
      guard store.token() == token else { return }
      if model.dialog == .changePassword { model.dialog = nil }
      model.notice("密码已修改")
    } catch {
      guard store.token() == token else { return }
      self.error = error.localizedDescription
    }
  }
}
