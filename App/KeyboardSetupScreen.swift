import SwiftUI
import UIKit

struct KeyboardSetupScreen: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.scenePhase) private var phase
  @ObservedObject var setup: KeyboardSetupCoordinator
  @State private var text = ""
  @State private var returnedFromSettings = false
  @FocusState private var focused: Bool

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            Text(setup.isComplete ? "设置完成，可以开始使用了" : "跟着下面三步，开启恋爱键盘")
              .font(.system(size: 20, weight: .bold))
            step(1, "添加恋爱键盘", "设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → 恋爱键盘")
            step(2, "允许完全访问", "点开「恋爱键盘」，开启「允许完全访问」。在线 AI 功能需要此权限。")
            step(3, "切换并验证", "返回这里，点下方输入框，长按键盘地球键，选择「恋爱键盘」。")
            if setup.isComplete {
              Label("已确认键盘启用和完全访问", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).accessibilityIdentifier("keyboardSetupComplete")
              LAButton(title: "开始使用") { focused = false; model.dialog = nil }
                .accessibilityIdentifier("keyboardSetupFinish")
            } else {
              LAButton(title: "去设置") {
                focused = false
                setup.willOpenSettings()
                model.openSettings()
              }.accessibilityIdentifier("keyboardSetupSettings")
              VStack(alignment: .leading, spacing: 10) {
                Text(returnedFromSettings ? "已返回，请切换到恋爱键盘完成验证" : "设置后在这里验证")
                  .font(.system(size: 14, weight: .semibold))
                  .accessibilityIdentifier("keyboardSetupStatus")
                TextField("点此唤起键盘", text: $text)
                  .font(.system(size: 16)).padding(14)
                  .background(LA.key, in: RoundedRectangle(cornerRadius: 12))
                  .focused($focused).autocorrectionDisabled().textInputAutocapitalization(.never)
                  .accessibilityIdentifier("keyboardSetupInput")
                Text("切换成功后会自动检测，不需要发送内容。若尚未完成，请检查是否已开启「允许完全访问」。")
                  .font(.system(size: 12)).foregroundStyle(LA.muted)
              }.id("keyboardSetupVerification")
              if !setup.error.isEmpty { Text(setup.error).font(.system(size: 12)).foregroundStyle(LA.accent) }
              Button("重新检测") { setup.prepare(); focused = true }
                .accessibilityIdentifier("keyboardSetupRecheck")
              Button("稍后设置") { focused = false; model.dialog = nil }
                .frame(maxWidth: .infinity).foregroundStyle(LA.muted)
                .accessibilityIdentifier("keyboardSetupLater")
            }
          }.padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }.background(LA.background).foregroundStyle(LA.ink)
          .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            if focused && !setup.isComplete {
              withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("keyboardSetupVerification", anchor: .top)
              }
            }
          }
          .navigationTitle("启用恋爱键盘").navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
              Button("关闭") { focused = false; model.dialog = nil }.accessibilityIdentifier("keyboardSetupClose")
            }
          }
      }
    }.task {
      setup.prepare()
      if phase == .active { resumeVerification() }
      // Poll only while the setup sheet is visible; no work is added to key presses.
      while !Task.isCancelled && !setup.isComplete {
        setup.checkCompletion()
        do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
      }
    }.onChange(of: phase) { _, newPhase in
      if newPhase != .active { focused = false }
      else { resumeVerification() }
    }.onChange(of: setup.isComplete) { _, complete in
      if complete { focused = false }
    }
  }
  private func resumeVerification() {
    if setup.didReturnFromSettings() {
      returnedFromSettings = true
      focused = !setup.isComplete
    }
  }
  private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(setup.isComplete ? "✓" : "\(number)")
        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
        .frame(width: 32, height: 32).background(LA.gradient, in: Circle())
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.system(size: 16, weight: .semibold))
        Text(detail).font(.system(size: 13)).foregroundStyle(LA.muted).fixedSize(horizontal: false, vertical: true)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
