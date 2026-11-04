import Foundation

public protocol HTTPTransport: Sendable {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
public struct URLSessionTransport: HTTPTransport {
  public init() {}
  public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw ClientError.message("服务响应无效") }
    return (data, response)
  }
}
public actor APIClient {
  public static let shared = APIClient()
  private let base: URL
  private let transport: any HTTPTransport
  public init(base: URL = Product.baseURL, transport: any HTTPTransport = URLSessionTransport()) {
    self.base = base
    self.transport = transport
  }
  private func send<T: Decodable & Sendable>(
    _ type: T.Type, url: URL, token: String? = nil, body: [String: Any]? = nil, mimo: Bool = false
  ) async throws -> T {
    var req = URLRequest(url: url)
    req.timeoutInterval = 80
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    if let token, !token.isEmpty {
      req.setValue(
        mimo ? token : "Bearer \(token)", forHTTPHeaderField: mimo ? "api-key" : "Authorization")
    }
    if let body {
      req.httpMethod = "POST"
      req.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let (data, response) = try await transport.data(for: req)
    try Task.checkCancellation()
    guard (200..<300).contains(response.statusCode) else {
      let message =
        (try? JSONDecoder().decode(ErrorResponse.self, from: data).message)
        ?? "请求失败（HTTP \(response.statusCode)）"
      throw ClientError.http(response.statusCode, message)
    }
    do { return try JSONDecoder().decode(type, from: data) } catch {
      throw ClientError.message("服务返回格式不正确，请稍后重试")
    }
  }
  private struct ErrorResponse: Decodable, Sendable { var message: String }
  private struct OK: Decodable, Sendable {}
  public func login(phone: String, password: String, register: Bool) async throws -> Session {
    guard phone.range(of: "^1[0-9]{10}$", options: .regularExpression) != nil else {
      throw ClientError.message("请输入正确的 11 位手机号")
    }
    guard (8...64).contains(password.count) else { throw ClientError.message("密码需为 8～64 位") }
    return try await send(
      Session.self, url: base.appendingPathComponent(register ? "auth/register" : "auth/login"),
      body: ["phone": phone, "password": password])
  }
  public func logout(token: String) async throws {
    _ = try await send(
      OK.self, url: base.appendingPathComponent("auth/logout"), token: token, body: [:])
  }
  public func config(token: String) async throws -> RuntimeConfig {
    let config = try await send(
      RuntimeConfig.self, url: base.appendingPathComponent("config"), token: token)
    guard config.schemaVersion == 1 else { throw ClientError.message("App 配置版本不支持，请升级 App") }
    return config
  }
  public func subscription(token: String) async throws -> Subscription {
    try await send(
      Subscription.self, url: base.appendingPathComponent("me/subscription"), token: token)
  }
  public func plans() async throws -> [Plan] {
    struct Response: Decodable, Sendable { var plans: [Plan] }
    return try await send(Response.self, url: base.appendingPathComponent("plans")).plans
  }
  public func alipayEnabled() async throws -> Bool {
    struct Response: Decodable, Sendable { var channels: [String] }
    return try await send(Response.self, url: base.appendingPathComponent("payment/channels"))
      .channels.contains("alipay")
  }
  public func createOrder(planID: String, requestID: String, token: String) async throws -> Order {
    try await send(
      Order.self, url: base.appendingPathComponent("orders"), token: token,
      body: ["planId": planID, "channel": "alipay", "requestId": requestID])
  }
  public func order(id: String, token: String) async throws -> Order {
    guard !id.isEmpty, !id.contains("/"), !id.contains("..") else {
      throw ClientError.message("订单号无效")
    }
    return try await send(
      Order.self, url: base.appendingPathComponent("orders").appendingPathComponent(id),
      token: token)
  }
  private struct Catalog: Decodable, Sendable {
    struct Item: Decodable, Sendable { var id: String }
    var data: [Item]
  }
  public func models(endpoint: Endpoint, key: String) async throws -> [String] {
    try validateKey(key)
    return try await send(
      Catalog.self, url: endpoint.validatedURL(path: "models"), token: key,
      mimo: endpoint.url.contains("xiaomimimo.com")
    ).data.map(\.id).sorted()
  }
  private struct Chat: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
      struct Message: Decodable, Sendable { var content: String? }
      var message: Message
    }
    var choices: [Choice]
  }
  private func validateKey(_ key: String) throws {
    guard !key.isEmpty, key.count <= 512, !key.contains(where: \.isWhitespace) else {
      throw ClientError.message("接口密钥格式无效")
    }
  }
  private func chat(
    url: URL, key: String, model: String, system: String, user: Any, thinking: Bool,
    mimo: Bool = false, temperature: Double = 0.75
  ) async throws -> String {
    var body: [String: Any] = [
      "model": model, "stream": false, "max_tokens": 4096, "temperature": temperature,
      "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
    ]
    if ThinkingPolicy.control(url: url, model: model) == .available {
      if thinking || model.lowercased().hasPrefix("kimi-") {
        body.removeValue(forKey: "temperature")
      }
      body["thinking"] = ["type": thinking ? "enabled" : "disabled"]
    }
    let result = try await send(Chat.self, url: url, token: key, body: body, mimo: mimo)
    guard
      let content = result.choices.first?.message.content?.trimmingCharacters(
        in: .whitespacesAndNewlines), !content.isEmpty
    else { throw ClientError.message("模型没有返回有效内容") }
    return content
  }
  public func test(endpoint: Endpoint, key: String) async throws {
    try validateKey(key)
    _ = try await chat(
      url: endpoint.validatedURL(), key: key, model: endpoint.model, system: "请简短回答", user: "请回答OK",
      thinking: endpoint.thinking, mimo: endpoint.url.contains("xiaomimimo.com"))
  }
  private func route(feature: String, endpoint: Endpoint?, key: String?, token: String?)
    async throws -> (URL, String, String, Bool, Bool)
  {
    var vip = false
    if let token, !token.isEmpty {
      let config = try await config(token: token)
      vip = config.user?.vip?.isActive == true
      let f =
        feature == "reply"
        ? config.features.replySuggestions
        : feature == "polish" ? config.features.superSpeak : config.features.visionReply
      if vip && f.enabled {
        return (
          base.appendingPathComponent(
            feature == "vision" ? "vision/reply" : "text/\(feature)/chat/completions"), token,
          f.model ?? "", f.thinkingEnabled ?? false, true
        )
      }
    }
    guard let endpoint, endpoint.isConfigured, let key, !key.isEmpty else {
      let name = feature == "vision" ? "视觉" : "文本"
      throw ClientError.message(vip
        ? "该功能尚未配置官方模型，请在 App「模型配置」中配置自己的\(name)模型参数"
        : "请开通 VIP，或在 App「模型配置」中配置自己的\(name)模型参数")
    }
    try validateKey(key)
    return (try endpoint.validatedURL(), key, endpoint.model, endpoint.thinking, false)
  }
  public func suggestions(
    text: String, relation: String?, settings: Settings, key: String?, token: String?
  ) async throws -> [String] {
    let feature = relation == nil ? "reply" : "polish"
    let (url, credential, model, thinking, official) = try await route(
      feature: feature, endpoint: settings.endpoint, key: key, token: token)
    var system: String
    if let relation {
      system =
        "你是恋爱沟通助手。用户面对的关系是：\(relation)。关系专属要求：\(settings.relationPrompts[relation] ?? Product.relationPrompts["通用"]!) 请把用户想说的话改写成3条自然、真诚、语气有差异且可直接发送的话术。只输出JSON字符串数组，必须正好3项，不要解释。"
    } else {
      system =
        settings.replyPrompt + "\n请针对对方消息生成3条语气和表达方式不同、均可直接发送的回复。只输出JSON字符串数组，必须正好3项，不要分析和解释。"
    }
    let content = try await chat(
      url: url, key: credential, model: model, system: system, user: text, thinking: thinking,
      mimo: !official && url.host?.contains("xiaomimimo.com") == true,
      temperature: relation == nil ? 0.8 : 0.75)
    return try Suggestions.parse(content)
  }
  public func vision(image: Data, settings: Settings, key: String?, token: String?) async throws
    -> VisionResult
  {
    guard image.count <= 6_000_000 else { throw ClientError.message("图片过大，请换一张截图") }
    let (url, credential, model, thinking, official) = try await route(
      feature: "vision", endpoint: settings.endpoint, key: key, token: token)
    if official {
      var result = try await send(
        VisionResult.self, url: url, token: credential,
        body: ["imageBase64": image.base64EncodedString(), "mime": "image/jpeg"])
      result.replies = try Suggestions.validate(result.replies)
      return result
    }
    let system =
      "识别聊天截图中对方最新的话，以用户本人的第一人称生成3条自然得体的回复。只输出JSON：{\"scenario\":\"恋爱|朋友|商务|家人|其他\",\"analysis\":\"不超过20字\",\"replies\":[\"稳妥回复\",\"进阶回复\",\"巧思回复\"]}"
    let content = try await chat(
      url: url, key: credential, model: model, system: system,
      user: [
        [
          "type": "image_url",
          "image_url": ["url": "data:image/jpeg;base64," + image.base64EncodedString()],
        ], ["type": "text", "text": "分析这张聊天截图"],
      ], thinking: thinking, mimo: url.host?.contains("xiaomimimo.com") == true)
    let clean = content.replacingOccurrences(of: "```json", with: "").replacingOccurrences(
      of: "```", with: ""
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    var result = try JSONDecoder().decode(VisionResult.self, from: Data(clean.utf8))
    result.replies = try Suggestions.validate(result.replies)
    return result
  }
  public func processVoice(text: String, mode: String, style: String, settings: Settings, key: String?, token: String?) async throws -> String {
    if mode == "听写" || mode == "润色" && style == "不润色" {
      return OutputRules.punctuation(text, preference: settings.punctuation)
    }
    let (url, credential, model, thinking, official) = try await route(
      feature: "polish", endpoint: settings.endpoint, key: key, token: token)
    let deep = mode == "润色" && StructuredExpression.needsStructure(text)
    let prompt = mode == "翻译" ? VoicePrompts.translation : VoicePrompts.prompt(style: style, settings: settings, deep: deep)
    let output = try await chat(url: url, key: credential, model: model, system: prompt, user: text, thinking: thinking,
      mimo: !official && url.host?.contains("xiaomimimo.com") == true, temperature: deep ? 0.15 : 0.1)
    if mode == "翻译" { return output }
    return OutputRules.punctuation(StructuredExpression.enforce(source: text, polished: output), preference: settings.punctuation)
  }
  public func transcribe(wav: Data, asrKey: String?, token: String?) async throws -> String {
    if let key = asrKey, !key.isEmpty {
      try validateKey(key)
      let response = try await send(
        Chat.self,
        url: URL(string: "https://api.xiaomimimo.com/v1/chat/completions")!, token: key,
        body: [
          "model": "mimo-v2.5-asr",
          "messages": [
            [
              "role": "user",
              "content": [
                [
                  "type": "input_audio",
                  "input_audio": ["data": "data:audio/wav;base64," + wav.base64EncodedString()],
                ]
              ],
            ]
          ],
        ], mimo: true)
      let text = OutputRules.transcript(response.choices.first?.message.content ?? "")
      guard !text.isEmpty else { throw ClientError.message("未识别到有效语音，请重试") }
      return text
    }
    guard let token, !token.isEmpty else {
      throw ClientError.message("请先打开 App 登录以使用语音输入，或配置自定义语音接口")
    }
    struct Response: Decodable, Sendable { var text: String }
    return try await send(
      Response.self, url: base.appendingPathComponent("speech/transcribe"), token: token,
      body: ["audioBase64": wav.base64EncodedString(), "format": "wav"]
    ).text
  }
}
