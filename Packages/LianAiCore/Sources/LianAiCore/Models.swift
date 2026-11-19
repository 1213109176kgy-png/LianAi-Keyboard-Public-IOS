import Foundation

public enum Product {
  public static let group = "group.com.bahuang.lianai.keyboard"
  public static let baseURL = URL(string: "https://lianai.bahuang.tech/api/app")!
  public static func dateLabel(milliseconds: Double) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date(timeIntervalSince1970: milliseconds / 1000))
  }
  public static let relations = ["通用", "心动对象", "恋人", "朋友", "客户", "上司", "同事", "家人"]
  public static let relationPrompts = [
    "通用": "把用户原话改写得自然、真诚、有分寸，保持原意和事实，不虚构信息。",
    "心动对象": "面对心动或暧昧对象，表达要自然、有吸引力但不过度热情，保留适度分寸和聊天空间。",
    "恋人": "面对恋人，语气亲密、真诚、有关心感，可以自然表达爱意，但不要油腻或强行承诺。",
    "朋友": "面对朋友，语气轻松自然、平等随和，可适度幽默，不制造暧昧或上下级口吻。",
    "客户": "面对客户，语气专业、礼貌、清晰，兼顾亲和力，不使用暧昧表达，不做未经确认的承诺。",
    "上司": "面对上司，语气尊重、简洁、可靠，说明重点和行动，不卑不亢，不使用过度亲密表达。",
    "同事": "面对同事，语气友好、协作、清晰，注意职场边界，不暧昧、不命令式表达。",
    "家人": "面对家人，语气温暖、耐心、真诚，重视关心和理解，避免生硬说教或夸张表达。",
  ]
  public static let replyPrompt = """
    你是“恋爱键盘”的聊天回复助手。用户会提供聊天对象发来的原话。
    你必须站在用户本人（消息接收者）的第一人称角度，直接生成一条可以发给对方的回复，不是在回答用户的问题，也不要替对方说话。
    回复要自然、真诚、有分寸，符合恋爱或暧昧聊天语境；保持原有事实，不虚构关系、经历、时间、地点或承诺。
    只输出可直接发送的回复正文，不要分析、标题、解释、引号、角色标签或“建议回复”等前缀。
    如果对方原话信息不足，生成一条自然且不过度承诺的回应，必要时用一个简短问题延续对话。
    """
}

public enum Provider: String, Codable, CaseIterable, Sendable {
  case custom, zhipu, qwen, deepseek, doubao, hunyuan
  public var title: String {
    switch self {
    case .custom: "自定义模型"
    case .zhipu: "智谱"
    case .qwen: "千问"
    case .deepseek: "DeepSeek"
    case .doubao: "豆包"
    case .hunyuan: "腾讯混元"
    }
  }
  public var url: String {
    switch self {
    case .custom: ""
    case .zhipu: "https://open.bigmodel.cn/api/paas/v4"
    case .qwen: "https://dashscope.aliyuncs.com/compatible-mode/v1"
    case .deepseek: "https://api.deepseek.com/v1"
    case .doubao: "https://ark.cn-beijing.volces.com/api/v3"
    case .hunyuan: "https://api.hunyuan.cloud.tencent.com/v1"
    }
  }
}
public struct Endpoint: Codable, Equatable, Sendable {
  public var name = ""
  public var provider = Provider.custom
  public var url = ""
  public var model = ""
  public var thinking = false
  public init() {}
  public var isConfigured: Bool { !url.isEmpty && !model.isEmpty }
  public func validatedURL(path: String = "chat/completions") throws -> URL {
    guard let u = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
      u.scheme == "https", u.host != nil, u.user == nil, u.password == nil, u.query == nil,
      u.fragment == nil
    else { throw ClientError.message("接口地址必须使用有效的 HTTPS 地址") }
    if u.path.hasSuffix("/" + path) { return u }
    let base =
      u.path.hasSuffix("/chat/completions")
      ? u.deletingLastPathComponent().deletingLastPathComponent() : u
    return base.appendingPathComponent(path)
  }
}
public struct Word: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var term: String
  public var hint: String
  public init(term: String, hint: String = "") {
    id = UUID()
    self.term = term
    self.hint = hint
  }
}
public struct HistoryEntry: Codable, Identifiable, Sendable {
  public var id: UUID
  public var date: Date
  public var kind: String
  public var content: String
  public init(kind: String, content: String) {
    id = UUID()
    date = Date()
    self.kind = kind
    self.content = content
  }
}
public struct Settings: Codable, Sendable {
  public var theme = "亮色模式"
  public var candidateSize = 18
  public var haptics = "适中"
  public var volume = 0.45
  public var punctuation = "智能标点"
  public var capitalize = true
  public var doubleSpace = false
  public var predictions = true
  public var predictionLearning = true
  public var layout = "九宫格拼音"
  public var startup = "拼音"
  public var symbols = ["，", "。", "？", "！", "…", "：", "、", "～"]
  public var clipboardHistory = false
  public var recentPaste = true
  public var retention = "从不"
  public var optimizeExpression = false
  public var endpoint: Endpoint?
  public var asrConfigured = false
  public var replyPrompt = Product.replyPrompt
  public var relationPrompts = Product.relationPrompts
  public var professional: [Word] = []
  public var typing: [Word] = []
  public var styles: [String: String] = [:]
  public var history: [HistoryEntry] = []
  public var clipboard: [Word] = []
  public var aiConsent = false
  public var keyboardModes = ["键盘", "帮你回", "超会说"]
  public init() {}
  public mutating func pruneHistory(now: Date = Date()) {
    let days: Double? =
      switch retention {
      case "从不": 0
      case "24小时": 1
      case "1周": 7
      case "1个月": 30
      default: nil
      }
    if let days { history.removeAll { days == 0 || now.timeIntervalSince($0.date) > days * 86400 } }
  }
  public mutating func record(kind: String, content: String) {
    pruneHistory()
    guard retention != "从不", !content.isEmpty else { return }
    history.insert(HistoryEntry(kind: kind, content: content), at: 0)
  }
}
public struct User: Codable, Sendable, Equatable {
  public var id: String
  public var phone: String?
  public var maskedPhone: String?
  public var displayPhone: String {
    maskedPhone ?? phone.map {
      $0.count == 11 ? String($0.prefix(3)) + "****" + String($0.suffix(4)) : $0
    } ?? "已登录"
  }
}
public struct Session: Codable, Sendable {
  public var token: String
  public var user: User
}
public struct Plan: Codable, Identifiable, Sendable, Equatable {
  public var id: String
  public var name: String
  public var description: String
  public var periodDays: Int
  public var priceFen: Int
  public var dailyQuota: Int
  public var sortOrder: Int?
  public var price: String {
    if priceFen == 0 { return "免费" }
    let amount = String(format: "%.2f", Double(priceFen) / 100)
      .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
      .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    return "¥" + amount
  }
  public var quota: String { dailyQuota == 0 ? "每日不限量" : "每日 \(dailyQuota) 次" }
}
public struct Subscription: Codable, Sendable {
  public var active: Bool
  public var planName: String
  public var dailyQuota: Int
  public var expiresAt: Double
  public var daysLeft: Int
}
public struct Order: Codable, Sendable {
  public var orderId: String?
  public var status: String
  public var payUrl: String?
  public var free: Bool?
}
public struct PendingPurchase: Codable, Sendable {
  public var userID: String
  public var requestID: String
  public var plan: Plan
  public var orderID: String
  public var payURL: String
  public init(userID: String, plan: Plan) {
    self.userID = userID
    self.plan = plan
    requestID = UUID().uuidString
    orderID = ""
    payURL = ""
  }
}
public struct Feature: Codable, Sendable {
  public var enabled: Bool
  public var modelId: String?
  public var model: String?
  public var endpoint: String?
  public var thinkingEnabled: Bool?
}
public struct RuntimeConfig: Codable, Sendable {
  public var schemaVersion: Int
  public struct ConfigUser: Codable, Sendable {
    public struct VIP: Codable, Sendable {
      public var active: Bool
      public var expiresAt: Double?
      public var isActive: Bool { active && (expiresAt ?? 0) > Date().timeIntervalSince1970 * 1000 }
    }
    public var vip: VIP?
  }
  public struct Features: Codable, Sendable {
    public var replySuggestions: Feature
    public var superSpeak: Feature
    public var visionReply: Feature
    public var speechRecognition: Feature
  }
  public var user: ConfigUser?
  public var features: Features
}
public struct VisionResult: Codable, Sendable {
  public var scenario: String
  public var analysis: String
  public var replies: [String]
}
public struct PreparedResult: Codable, Sendable {
  public var id = UUID()
  public var date = Date()
  public var userID: String?
  public var kind: String
  public var text: String
  public init(userID: String?, kind: String, text: String) {
    self.userID = userID
    self.kind = kind
    self.text = text
  }
  public func isValid(userID: String?, now: Date = Date()) -> Bool {
    self.userID == userID && now.timeIntervalSince(date) < 600
  }
}
public enum ClientError: LocalizedError, Sendable {
  case http(Int, String)
  case message(String)
  public var errorDescription: String? {
    switch self {
    case .http(_, let s), .message(let s): s
    }
  }
}
public enum PaymentPolicy {
  public static func validatedPaymentURL(_ text: String) throws -> URL {
    guard let u = URL(string: text), u.scheme == "https",
      ["openapi.alipay.com", "openapi.alipaydev.com"].contains(u.host?.lowercased() ?? ""),
      u.user == nil, u.password == nil, u.port == nil || u.port == 443
    else { throw ClientError.message("支付地址无效，请查询订单或联系管理员") }
    return u
  }
  public static func isReturn(_ u: URL) -> Bool {
    u.scheme == "lianai" && u.host == "payment-return"
  }
  public static func terminal(_ status: String) -> Bool {
    ["paid", "expired", "closed"].contains(status)
  }
}
public struct InsertTracker: Sendable {
  private var text: String?
  private var context: String?
  public init() {}
  public mutating func remember(text: String, before: String?) {
    self.text = text
    context = before
  }
  public mutating func invalidate() {
    text = nil
    context = nil
  }
  public func replacementDeletionCount(before: String?, selected: String?) -> Int {
    guard selected?.isEmpty != false, let text, let context, let before, before == context,
      before.hasSuffix(text)
    else { return 0 }
    return text.count
  }
}
public enum Suggestions {
  public static func parse(_ text: String) throws -> [String] {
    var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if cleaned.hasPrefix("```") {
      cleaned = cleaned.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
      if cleaned.hasSuffix("```") { cleaned.removeLast(3) }
    }
    guard let data = cleaned.data(using: .utf8),
      let values = try? JSONDecoder().decode([String].self, from: data)
    else { throw ClientError.message("模型返回格式不正确，请重新生成") }
    return try validate(values)
  }
  public static func validate(_ values: [String]) throws -> [String] {
    var result: [String] = []
    for value in values {
      let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
      if !v.isEmpty && !result.contains(v) { result.append(v) }
    }
    guard result.count >= 3 else { throw ClientError.message("模型未返回三条有效回复") }
    return Array(result.prefix(3))
  }
  public static func emotion(_ text: String) -> String {
    if ["难过", "伤心", "生气", "失望", "讨厌", "不开心"].contains(where: text.contains) { return "需要安慰" }
    if ["吗", "呢", "一起", "想请", "有空", "期待"].contains(where: text.contains) { return "开心期待" }
    return "友好交流"
  }
}
