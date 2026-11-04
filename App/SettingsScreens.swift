import AVFAudio
import LianAiCore
import SwiftUI
import UniformTypeIdentifiers

struct KeyboardSettingsScreen: View {
  let page: Page
  @EnvironmentObject private var store: SharedStore
  @EnvironmentObject private var model: AppModel
  @State private var symbol = ""
  @State private var oldSymbol: String?
  @State private var editSymbol = false
  private func binding<T>(_ path: WritableKeyPath<Settings, T>) -> Binding<T> {
    Binding(get: { store.settings[keyPath: path] }, set: { store.settings[keyPath: path] = $0 })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) { content }.alert(
      oldSymbol == nil ? "添加九宫格符号" : "编辑九宫格符号", isPresented: $editSymbol
    ) {
      TextField("输入一个符号", text: $symbol)
      Button("保存") {
        let value = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if let oldSymbol, let i = store.settings.symbols.firstIndex(of: oldSymbol) {
          store.settings.symbols[i] = value
        } else if store.settings.symbols.count < 16 {
          store.settings.symbols.append(value)
        }
        store.settings.symbols =
          Array(NSOrderedSet(array: store.settings.symbols)) as? [String] ?? store.settings.symbols
      }
      if oldSymbol != nil {
        Button("删除", role: .destructive) {
          store.settings.symbols.removeAll { $0 == oldSymbol }
          if store.settings.symbols.isEmpty { store.settings.symbols = Settings().symbols }
        }
      }
      Button("取消", role: .cancel) {}
    }
  }
  @ViewBuilder private var content: some View {
    switch page {
    case .layout:
      Card(spacing: 0) {
        KeyboardPreview()
        SettingTitle("外观")
        Segments(labels: ["暗黑模式", "亮色模式", "自适应系统"], value: binding(\.theme))
      }
      Card(spacing: 0) {
        KeyboardPreview(size: store.settings.candidateSize)
        SettingTitle("候选词大小")
        Segments(
          labels: ["12", "14", "16", "默认", "20", "22", "24"],
          value: Binding(
            get: {
              store.settings.candidateSize == 18 ? "默认" : String(store.settings.candidateSize)
            }, set: { store.settings.candidateSize = Int($0) ?? 18 }))
      }
    case .effects:
      Card(spacing: 0) {
        OperationGuide(text: "选择适合自己的触感强度\n每次按键会按当前强度反馈")
        SettingTitle("触感强度")
        Segments(labels: ["无", "系统", "弱", "适中", "较强", "强"], value: binding(\.haptics))
      }
      Card(spacing: 0) {
        OperationGuide(text: "拖动滑块调整按键音量\n拖到最左侧即可静音")
        SettingTitle("按键音量")
        BrandSlider(value: binding(\.volume))
      }
    case .auxiliary:
      Card(spacing: 0) {
        OperationGuide(text: "选择听写与润色结果的标点规则\n设置会在下一次输出时生效")
        SettingTitle("标点习惯")
        Segments(labels: ["智能标点", "空格代替标点", "句末不添加标点"], value: binding(\.punctuation))
      }
      SettingToggle(title: "英文首字母自动大写", guide: "开启后，英文句首会自动使用大写字母", value: binding(\.capitalize))
      SettingToggle(
        title: "双击空格输入句号", guide: "连续双击文字键盘的空格键\n会输入一个句号并保留正常空格逻辑", value: binding(\.doubleSpace))
      SettingToggle(
        title: "联想词", guide: "完成输入后，在候选栏显示下一词建议\n开始输入拼音或英文时会立即恢复正常候选", value: binding(\.predictions)
      )
      SettingToggle(
        title: "本机联想学习", guide: "仅记录已确认词与下一词的使用次数\n不会保存完整句子、拼音或可浏览的输入历史",
        value: binding(\.predictionLearning))
    case .management:
      Card(spacing: 0) {
        OperationGuide(text: "选择每次调出输入法时最先显示的模式\n未开启的模式不会出现在可选列表中")
        SettingTitle("每次调出默认模式")
        ChoiceField(title: "每次调出默认模式", choices: ["默认（上次使用的模式）", "超会说", "拼音", "英文", "帮你回"], value: binding(\.startup))
      }
      Card(spacing: 0) {
        OperationGuide(text: "选择 26 键全键盘或九宫格拼音\n切换后在下一次打开键盘时应用")
        SettingTitle("中文主键盘")
        Segments(labels: ["26键全键盘拼音", "九宫格拼音"], value: binding(\.layout))
      }
      Card(spacing: 0) {
        OperationGuide(text: "点击符号可编辑\n长按右侧拖动柄可调整符号顺序\n九宫格逗号键的弹出面板会按此顺序显示")
        SettingTitle("九宫格符号")
        VStack(spacing: 4) {
          ForEach(store.settings.symbols, id: \.self) { value in
            HStack(spacing: 0) {
              Button(value) {
                oldSymbol = value
                symbol = value
                editSymbol = true
              }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 14)
              Icon(name: "grip_vertical", size: 20).frame(width: 44, height: 48)
                .contentShape(Rectangle()).draggable(value).accessibilityElement(children: .ignore).accessibilityHidden(false).accessibilityLabel("拖动排序" + value)
            }.font(.system(size: 14)).foregroundStyle(LA.ink)
              .frame(height: 48).background(LA.panel, in: RoundedRectangle(cornerRadius: 14))
              .overlay(RoundedRectangle(cornerRadius: 14).stroke(LA.key, lineWidth: 1))
              .dropDestination(for: String.self) { values, _ in
                guard let source = values.first, source != value,
                  let from = store.settings.symbols.firstIndex(of: source),
                  let to = store.settings.symbols.firstIndex(of: value) else { return false }
                let moved = store.settings.symbols.remove(at: from)
                store.settings.symbols.insert(moved, at: to)
                return true
              }
          }
        }
        LAButton(title: "添加符号", filled: false) {
          oldSymbol = nil
          symbol = ""
          editSymbol = true
        }
      }
    case .clipboard:
      SettingToggle(
        title: "剪贴板历史", guide: "复制的内容会显示在这里\n点击内容即可粘贴\n向左滑动可删除", value: binding(\.clipboardHistory))
      SettingToggle(
        title: "最近复制快速粘贴", guide: "在键盘点击粘贴，插入最近复制的文字\niOS 需用户主动粘贴，不自动读取剪贴板或判断复制时间",
        value: binding(\.recentPaste))
    default: EmptyView()
    }
  }
}
struct OptimizeScreen: View {
  @EnvironmentObject private var store: SharedStore
  @EnvironmentObject private var model: AppModel
  @StateObject private var dictionary = DictionaryManager.shared
  @State private var adding = false
  @State private var type = "专业词库"
  @State private var word = ""
  @State private var hint = ""
  @State private var package = ""
  @State private var style = "办公正式"
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionLabel("离线词典增强")
      Card {
        Hint("扩展词汇、腾讯词汇、英文混输与 Emoji\n随安装包内置，首次使用自动启用，无需联网下载")
        Text("增强词典").font(.system(size: 14, weight: .bold))
        Text("已启用 · 内置增强词典，离线可用").font(.system(size: 14))
      }
      Card {
        Hint("改善长句切分、上下文排序与整句候选\n约 400 MB，仅在主动下载后启用")
        Text("万象长句增强").font(.system(size: 14, weight: .bold))
        Hint(dictionary.status)
        if dictionary.downloading { ProgressView(value: dictionary.progress).tint(LA.accent) }
        LAButton(title: dictionary.installed ? "移除长句增强" : "下载长句增强", busy: dictionary.downloading) {
          Task {
            do {
              if dictionary.installed {
                try dictionary.remove()
              } else {
                try await dictionary.download()
              }
            } catch { model.notice(error.localizedDescription) }
          }
        }
      }
      LAButton(title: "添加词条") { adding = true }
      SectionLabel("专业词库")
      wordList(store.settings.professional, professional: true)
      SectionLabel("打字词典")
      wordList(store.settings.typing, professional: false)
      SectionLabel("应用文风")
      Card {
        Hint("输入应用包名后选择文风\niOS 不提供稳定的宿主包名识别，配置会保存，自动按应用切换不可用")
        Field(title: "应用包名", text: $package)
        Segments(labels: ["办公正式", "聊天自然", "笔记简洁", "不润色"], value: $style)
        LAButton(title: "保存应用文风") {
          guard !package.trimmingCharacters(in: .whitespaces).isEmpty else {
            model.notice("请输入应用包名")
            return
          }
          store.settings.styles[package] = style
          package = ""
        }
      }
      ForEach(store.settings.styles.keys.sorted(), id: \.self) { key in
        Card {
          HStack {
            Text("\(key) · \(store.settings.styles[key] ?? "")").font(.system(size: 13))
            Spacer()
            Button("删除", role: .destructive) { store.settings.styles.removeValue(forKey: key) }
              .font(.system(size: 12))
          }
        }
      }
      SettingToggle(
        title: "优化表达", guide: "开启后，分类和分点表达会自动整理\n仅影响对应润色流程，不改动手动输入内容",
        value: Binding(
          get: { store.settings.optimizeExpression },
          set: { store.settings.optimizeExpression = $0 }))
    }.sheet(isPresented: $adding) {
      VStack(spacing: 16) {
        Text("添加词条").font(.headline)
        Segments(labels: ["专业词库", "打字词典"], value: $type)
        Field(title: "单词或词语", text: $word)
        Field(title: "拼音或备注（可选）", text: $hint)
        LAButton(title: "添加") {
          let t = word.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !t.isEmpty else { return }
          let item = Word(term: t, hint: hint)
          if type == "专业词库" {
            store.settings.professional.removeAll { $0.term == t }
            store.settings.professional.append(item)
            store.settings.professional.sort {
              let left = $0.term.utf8.map { (65...90).contains($0) ? $0 + 32 : $0 }
              let right = $1.term.utf8.map { (65...90).contains($0) ? $0 + 32 : $0 }
              return left.lexicographicallyPrecedes(right)
            }
          } else {
            store.settings.typing.removeAll { $0.term == t }
            store.settings.typing.insert(item, at: 0)
          }
          word = ""
          hint = ""
          adding = false
        }
        LAButton(title: "取消", filled: false) { adding = false }
      }.padding(24).background(LA.background).presentationDetents([.height(360)])
    }
  }
  @ViewBuilder private func wordList(_ values: [Word], professional: Bool) -> some View {
    if values.isEmpty {
      Card {
        Hint(
          professional
            ? "尚未添加自定义专业词\n用于人名、公司名和行业术语，辅助拼音候选及 AI 润色" : "尚未添加自定义打字词\n用于常用词、短语及英文词，辅助输入候选")
        LAButton(title: professional ? "添加专业词" : "添加打字词", filled: false) {
          type = professional ? "专业词库" : "打字词典"
          adding = true
        }
      }
    } else {
      ForEach(values) { item in
        Card {
          HStack {
            Text(item.term + (item.hint.isEmpty ? "" : " · " + item.hint)).font(.system(size: 14))
            Spacer()
            Button("删除", role: .destructive) {
              if professional {
                store.settings.professional.removeAll { $0.id == item.id }
              } else {
                store.settings.typing.removeAll { $0.id == item.id }
              }
            }.font(.system(size: 12))
          }
        }
      }
    }
  }
}
struct LocalDataScreen: View {
  @EnvironmentObject private var store: SharedStore
  @EnvironmentObject private var model: AppModel
  @State private var importer = false
  @State private var dictionaryInfo = false
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Card {
        OperationGuide(text: "选择自动保留时长\n选择“从不”会立即清除已有历史")
        Text("历史记录").font(.system(size: 14, weight: .bold))
        Segments(
          labels: ["从不", "24小时", "1周", "1个月", "永久"],
          value: Binding(
            get: { store.settings.retention },
            set: {
              store.settings.retention = $0
              store.settings.pruneHistory()
            }))
        ActionRow(title: "删除全部历史记录", destructive: true) { store.settings.history = [] }
      }
      SectionLabel("最近记录")
      if store.settings.history.isEmpty { Hint("暂无保留的历史记录") }
      ForEach(store.settings.history.prefix(100)) { h in
        Card {
          Text("\(h.kind) · \(h.date.formatted(date: .numeric, time: .shortened))").font(
            .system(size: 12)
          ).foregroundStyle(LA.muted)
          Text(h.content).font(.system(size: 14)).textSelection(.enabled)
        }
      }
      Card {
        Hint("候选与学习数据只保留在设备本地\n清除学习数据不会删除专业词和打字词典")
        Text("中文离线输入").font(.system(size: 14, weight: .bold))
        ActionRow(title: "离线拼音词典", detail: "Rime-Ice 增强包，安装后直接可用") { dictionaryInfo = true }
        Divider()
        ActionRow(title: "清除候选学习数据") {
          UserDefaults(suiteName: Product.group)?.removeObject(forKey: "englishLearning")
          UserDefaults(suiteName: Product.group)?.set(
            UUID().uuidString, forKey: "clearRimeLearning")
          model.notice("下次打开键盘时清除本机候选学习数据")
        }
        Divider()
        ActionRow(title: "清除联想学习数据", detail: "不会删除专业词、打字词典或历史记录") {
          UserDefaults(suiteName: Product.group)?.removeObject(forKey: "predictionPairs")
          UserDefaults(suiteName: Product.group)?.removeObject(forKey: "predictionLearningV2")
          UserDefaults(suiteName: Product.group)?.set(
            UUID().uuidString, forKey: "clearPredictionLearning")
          model.notice("已清除本机联想学习数据")
        }

      }
    }.confirmationDialog("离线词典", isPresented: $dictionaryInfo, titleVisibility: .visible) {
      Button("导入本地词典") { importer = true }
      Button("关闭", role: .cancel) {}
    } message: {
      Text("当前：内置 Rime-Ice 增强包\n已包含预编译词典，离线可用。支持导入词语与拼音的文本词典。")
    }.fileImporter(isPresented: $importer, allowedContentTypes: [.plainText, .data]) { result in
      do {
        let url = try result.get()
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count < 8_000_000, let text = String(data: data, encoding: .utf8) else {
          throw ClientError.message("请导入小于 8MB 的 UTF-8 文本词典")
        }
        let entries = text.split(whereSeparator: \.isNewline).prefix(50000).compactMap {
          line -> Word? in
          let fields = line.split(whereSeparator: \.isWhitespace)
          guard let term = fields.first, !term.hasPrefix("#"), fields.count >= 2 else { return nil }
          return Word(term: String(term), hint: String(fields[1]))
        }
        store.settings.typing = Array((store.settings.typing + entries).suffix(50000))
        model.notice("已导入 \(entries.count) 条本地词条")
      } catch { model.notice(error.localizedDescription) }
    }
  }
}
struct PermissionScreen: View {
  @EnvironmentObject private var model: AppModel
  @State private var mic = AVAudioApplication.shared.recordPermission == .granted
  var body: some View {
    VStack(spacing: 12) {
      Card {
        Hint("依次完成输入法和录音授权\n在线 AI 还需允许键盘完全访问")
        Text("输入法与系统权限").font(.system(size: 14, weight: .bold))
        ActionRow(title: "启用恋爱键盘") { model.dialog = .setup }
        Divider()
        ActionRow(title: "切换输入法") { model.dialog = .setup }
        Divider()
        ActionRow(title: "录音权限") {
          AVAudioApplication.requestRecordPermission { @Sendable allowed in
            Task { @MainActor in
              mic = allowed
              if allowed { model.dialog = .voice } else { model.openSettings() }
            }
          }
        }
        Divider()
        ActionRow(title: "横屏悬浮窗", detail: "iOS 使用系统键盘区域，不能启用全局悬浮窗") {
          model.notice("iOS 不支持安卓全局悬浮窗，横屏键盘会自动适配系统区域")
        }
      }
      Hint("麦克风权限：\(mic ? "已授权" : "未授权")")
    }
  }
}
struct AboutScreen: View {
  @EnvironmentObject private var model: AppModel
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Card {
        ActionRow(title: "版本信息", detail: "当前版本 1.5.9（39）· iOS") { model.dialog = .version }
        Divider()
        ActionRow(title: "隐私政策", detail: "数据如何采集与保存") { model.dialog = .privacy }
      }
      SectionLabel("开发者与交流")
      Card {
        Text("开发者：邝广元").font(.system(size: 14, weight: .bold))
        Hint("下面是我的微信，欢迎添加我为好友，一起沟通交流恋爱键盘的使用体验、建议和想法。")
        Image("developer").resizable().scaledToFit()
      }
      SectionLabel("随缘打赏")
      Card {
        Hint("如果你觉得这个项目对你有帮助，欢迎随缘打赏。感谢你的支持与鼓励。")
        Hint("微信收款码")
        Image("donation").resizable().scaledToFit()
      }

    }
  }
}
struct GuideScreen: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionLabel("语音与文本")
      Card {
        guide("cloud", "配置模型", "进入大模型配置，可订阅官方通道，或填写服务商、API Key 和模型。语音自配使用小米 MiMo ASR。")
        Divider()
        guide("mic", "听写与润色", "先开启键盘语音会话，返回聊天后长按空格直接说话，松开后识别并回填。开启后持续可用，App 被结束或系统音频中断后需重新开启。")
      }
      SectionLabel("文字键盘")
      Card {
        guide("keyboard", "切换中文与英文", "顶部选择键盘，点击 ABC 或中/EN 切换；在键盘管理中选择 26 键或九宫格。")
        Divider()
        guide("sliders_horizontal", "快速输入标点", "九宫格的「，。?!」键展开标点条，选择其他标点自动替换预插的逗号。")
        Divider()
        guide("smile", "颜文字与符号", "九宫格 ^_^ 打开颜文字条，符号共三页，Emoji 可按分类浏览。")
        Divider()
        guide("settings_2", "横屏键盘", "iOS 横屏会在系统输入区域中适配，不支持覆盖其他 App 的全局悬浮窗口。")
      }
      SectionLabel("帮你回")
      Card {
        guide("wand_sparkles", "生成回复", "复制对方消息，点击「粘贴TA的话」生成三条建议。点击使用，支持重新分析。")
        Divider()
        guide("message_circle_more", "截图识别回复", "选择聊天截图，由视觉模型分析场景并生成回复。发送前请结合真实语境检查。")
      }
      SectionLabel("超会说")
      Card { guide("wand_sparkles", "优化表达", "先在键盘内部输入草稿，选择关系，点击优化生成三条话术。点击选中的话术才写入聊天输入框。") }
    }
  }
  private func guide(_ icon: String, _ title: String, _ detail: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Icon(name: icon).foregroundStyle(LA.accent)
      VStack(alignment: .leading, spacing: 7) {
        Text(title).font(.system(size: 14, weight: .bold))
        Hint(detail)
      }
    }.padding(.vertical, 6)
  }
}
