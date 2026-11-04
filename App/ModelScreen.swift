import LianAiCore
import SwiftUI

struct ModelScreen: View {
  @EnvironmentObject private var store: SharedStore
  @EnvironmentObject private var model: AppModel
  @State private var expanded = false
  @State private var tab = "多模态模型"
  @State private var asrKey = ""
  @State private var editing = false
  @State private var reply = ""
  @State private var relation = "通用"
  @State private var relationPrompt = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionLabel("AI 大模型套餐")
      Card {
        Hint("开通 VIP 后使用后台为各项功能配置的官方模型，无需填写接口参数。")
        LAButton(title: "查看订阅套餐") { model.navigate(.subscription) }
        Button {
          withAnimation {
            expanded.toggle()
            if expanded { tab = "多模态模型" }
          }
        } label: {
          HStack {
            Text("不想订阅？使用自定义模型").font(.system(size: 13))
            Spacer()
            Icon(name: "chevron_down", size: 18).rotationEffect(.degrees(expanded ? 180 : 0))
          }.foregroundStyle(LA.accent).padding(.top, 6)
        }
      }
      if expanded {
        SectionLabel("自定义模型")
        Segments(labels: ["多模态模型", "ASR 模型"], value: $tab)
        if tab == "多模态模型" {
          if let endpoint = store.settings.endpoint {
            Card {
              Hint("此模型同时用于帮你回、截图识别回复和超会说。点击可修改参数或删除。")
              ActionRow(
                title: endpoint.name.isEmpty
                  ? "\(endpoint.provider.title) · \(endpoint.model)" : endpoint.name,
                detail: "\(endpoint.provider.title) · \(endpoint.model)"
              ) { editing = true }
            }
          } else {
            ModelEditor(isInline: true)
          }
        } else {
          Card {
            Hint("语音输入（录音转文字）使用小米 MiMo 语音识别。前往小米 MiMo 开放平台创建 API Key 后填入即可。")
            Field(title: "输入小米 MiMo API Key", text: $asrKey, secure: true)
            HStack {
              Spacer()
              LAButton(title: "保存") {
                do {
                  guard !asrKey.trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw ClientError.message("请填写 API Key")
                  }
                  try SecretStore.write(
                    asrKey.trimmingCharacters(in: .whitespacesAndNewlines), key: "asrKey")
                  KeyboardVoiceService.shared.stop(message: "语音配置已更改，请重新开启会话")
                  store.settings.asrConfigured = true
                  model.notice("ASR 模型已保存，语音输入已就绪")
                } catch { model.notice(error.localizedDescription) }
              }.frame(width: 140)
            }
          }
        }
      }
      SectionLabel("帮你回提示词")
      Card {
        Hint("定义 AI 以谁的角度回复、回复什么内容。该提示词会作为系统提示词发送给文本模型。")
        editor($reply)
        HStack {
          LAButton(title: "恢复默认", filled: false) { reply = Product.replyPrompt }
          LAButton(title: "保存提示词") {
            store.settings.replyPrompt =
              reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              ? Product.replyPrompt : reply
            model.notice("帮你回提示词已保存")
          }
        }
      }
      SectionLabel("超会说关系提示词")
      Card {
        Hint("为每一种聊天对象配置独立的系统提示词。键盘选择关系后，AI会自动使用对应配置。")
        ChoiceField(title: "选择聊天关系", choices: Product.relations, value: $relation)
        editor($relationPrompt)
        HStack {
          LAButton(title: "恢复默认", filled: false) {
            relationPrompt = Product.relationPrompts[relation] ?? ""
          }
          LAButton(title: "保存当前关系") {
            store.settings.relationPrompts[relation] =
              relationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              ? Product.relationPrompts[relation] : relationPrompt
            model.notice("\(relation) 提示词已保存")
          }
        }
      }
    }.onAppear {
      expanded = store.settings.endpoint != nil
      asrKey = SecretStore.read(key: "asrKey") ?? ""
      reply = store.settings.replyPrompt
      relationPrompt = store.settings.relationPrompts[relation] ?? ""
    }.onChange(of: relation) { _, value in
      relationPrompt = store.settings.relationPrompts[value] ?? ""
    }.appModal(isPresented: $editing) {
      ScrollView {
        VStack(spacing: 12) {
          HStack {
            Text("编辑大模型").font(.system(size: 20, weight: .bold))
            Spacer()
            Button("关闭") { editing = false }.tint(LA.accent)
          }
          ModelEditor(isInline: false) { editing = false }
        }.padding(20)
      }.background(LA.background)
    }
  }
  private func editor(_ text: Binding<String>) -> some View {
    TextEditor(text: text).font(.system(size: 12)).scrollContentBackground(.hidden).frame(
      height: 112
    ).padding(10).background(LA.panel, in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(LA.key, lineWidth: 1))
  }
}
struct ModelEditor: View {
  let isInline: Bool
  var didSave: () -> Void = {}
  @EnvironmentObject private var store: SharedStore
  @EnvironmentObject private var model: AppModel
  @State private var endpoint = Endpoint()
  @State private var key = ""
  @State private var busy = false
  @State private var reading = false
  @State private var models: [String] = []
  @State private var choose = false
  @State private var deleting = false
  @State private var customURL = Endpoint().url
  init(isInline: Bool, didSave: @escaping () -> Void = {}) {
    self.isInline = isInline
    self.didSave = didSave
    let saved = SharedStore.shared.settings.endpoint ?? Endpoint()
    _endpoint = State(initialValue: saved)
    _customURL = State(initialValue: saved.provider == .custom ? saved.url : "")
    _key = State(initialValue: SecretStore.read(key: "modelKey") ?? "")
  }
  private var thinkingControl: ThinkingPolicy.Control {
    guard let url = URL(string: endpoint.url) else { return .unsupported }
    return ThinkingPolicy.control(url: url, model: endpoint.model)
  }
  var body: some View {
    Card {
      if isInline {
        Hint("填写服务商与接口参数。保存后自动用于帮你回、截图识别回复和超会说。")
      } else {
        Hint("配置名称")
        Field(title: "如：我的 DeepSeek", text: $endpoint.name)
      }
      Hint("模型服务商")
      ChoiceField(title: "模型服务商", choices: Provider.allCases.map(\.title), value: Binding(
        get: { endpoint.provider.title },
        set: { title in
          guard let provider = Provider.allCases.first(where: { $0.title == title }) else { return }
          endpoint.provider = provider
        }))
      if endpoint.provider == .custom {
        Hint("接口地址")
        Field(title: "https://api.example.com/v1", text: $endpoint.url).keyboardType(.URL)
      } else {
        Hint("官方接口：\(endpoint.url)")
      }
      Hint("API Key")
      Field(title: "输入 API Key", text: $key, secure: true)
      Hint("模型名称")
      HStack {
        Field(title: "输入或读取模型名称", text: $endpoint.model)
        LAButton(title: "读取模型", filled: false, busy: reading) {
          Task {
            reading = true
            defer { reading = false }
            do {
              models = try await APIClient.shared.models(endpoint: endpoint, key: key)
              if models.isEmpty { model.notice("该接口暂未返回可选模型，可手动填写模型名") } else { choose = true }
            } catch { model.notice(error.localizedDescription) }
          }
        }.frame(width: 100)
      }
      Toggle(
        "思考模式",
        isOn: Binding(
          get: { thinkingControl == .required || endpoint.thinking },
          set: { endpoint.thinking = $0 })
      ).font(.system(size: 14)).tint(LA.accent).disabled(thinkingControl != .available)
      Hint(
        thinkingControl == .required
          ? "此模型固定开启思考，服务商不支持关闭。"
          : thinkingControl == .available ? "默认关闭，直接生成回复；开启后可能增加等待时间和用量。" : "此模型暂未适配思考开关，使用服务商默认行为。"
      )
      HStack {
        LAButton(title: "测试连接", filled: false, busy: busy) {
          Task {
            busy = true
            defer { busy = false }
            do {
              guard !endpoint.model.isEmpty else { throw ClientError.message("请完整填写接口信息") }
              try await APIClient.shared.test(endpoint: endpoint, key: key)
              model.notice("连接成功")
            } catch { model.notice(error.localizedDescription) }
          }
        }
        LAButton(title: "保存配置", busy: busy) { save() }
      }
      if !isInline { LAButton(title: "删除模型", filled: false) { deleting = true } }
    }.onChange(of: endpoint.provider) { old, value in
      if old == .custom { customURL = endpoint.url }
      endpoint.url = value == .custom ? customURL : value.url
      endpoint.model = ""
    }
    .appModal(isPresented: $choose) {
      VStack {
        Text("选择模型").font(.headline).padding()
        ForEach(models, id: \.self) { value in
          LAButton(title: value, filled: false) {
            endpoint.model = value
            choose = false
          }
        }
        Button("关闭") { choose = false }.padding()
      }.tint(LA.accent)
    }
    .confirmationDialog("删除模型？", isPresented: $deleting, titleVisibility: .visible) {
      Button("确认删除", role: .destructive) {
        do {
          try SecretStore.write("", key: "modelKey")
          store.settings.endpoint = nil
          didSave()
          model.notice("模型已删除")
        } catch { model.notice(error.localizedDescription) }
      }
      Button("取消", role: .cancel) {}
    } message: {
      Text("删除后，关联业务将恢复为未配置，可重新添加。")
    }
  }
  private func save() {
    do {
      guard endpoint.isConfigured, !key.isEmpty, key.count <= 512,
        !key.contains(where: \.isWhitespace), endpoint.model.count <= 128,
        !endpoint.model.contains(where: \.isWhitespace)
      else { throw ClientError.message("请完整填写有效的接口地址、密钥与模型名称") }
      _ = try endpoint.validatedURL()
      try SecretStore.write(key, key: "modelKey")
      if endpoint.name.isEmpty { endpoint.name = "\(endpoint.provider.title) · \(endpoint.model)" }
      store.settings.endpoint = endpoint
      model.notice("已保存")
      didSave()
    } catch { model.notice(error.localizedDescription) }
  }
}
