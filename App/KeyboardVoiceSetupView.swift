import LianAiCore
import SwiftUI

struct KeyboardVoiceSetupView: View {
  @EnvironmentObject private var model: AppModel
  @ObservedObject private var voice = KeyboardVoiceService.shared
  var body: some View {
    DialogCard(title: "键盘语音输入", subtitle: "开启后，返回聊天长按空格直接说话") {
      Hint("会话期间麦克风保持开启，系统会显示橙色指示灯。只有你按下语音键时才处理音频，其余音频立即丢弃；开启后持续可用，可随时手动关闭；App 被结束或系统音频中断后需重新开启。")
      Hint("优先使用已配置的小米 MiMo 语音接口或官方登录通道，音频会发送给对应服务识别；均未配置时使用 Apple 语音识别，优先本机，不支持时使用 Apple 在线服务。不会自动发送聊天消息。")
      Text(voice.state.message.isEmpty ? "尚未开启语音会话" : voice.state.message)
        .font(.system(size: 14, weight: .semibold)).accessibilityIdentifier("voiceSessionStatus")
      if voice.state.isLive() {
        LAButton(title: "返回键盘试用") { model.dialog = nil; model.page = .test }
        LAButton(title: "关闭语音会话", filled: false) { voice.stop() }
      } else {
        LAButton(title: "开启键盘语音", busy: voice.enabling) { Task { await voice.enable() } }
        LAButton(title: "去系统设置", filled: false) { model.openSettings() }
      }
    }
  }
}
