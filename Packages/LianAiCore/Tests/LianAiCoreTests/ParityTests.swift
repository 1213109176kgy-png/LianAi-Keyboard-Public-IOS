import XCTest
@testable import LianAiCore

@MainActor
final class ParityTests: XCTestCase {
  func testKeyboardPaletteRetainsEveryAndroidEntryAndTokenBoundary() {
    XCTAssertEqual(KeyboardPalette.emojis.map(\.count), [40, 65, 50, 32, 40, 45, 42])
    XCTAssertEqual(KeyboardPalette.emojis[0][15], "❤️")
    XCTAssertEqual(KeyboardPalette.symbols.count, 3)
    XCTAssertTrue(KeyboardPalette.symbols.allSatisfy { $0.count == 3 && $0.allSatisfy { $0.count == 10 } })
    XCTAssertEqual(KeyboardPalette.symbols[2][1][1...2], ["——", "……"])
    XCTAssertEqual(KeyboardPalette.kaomoji, ["^_^", "^o^", "^3^", ">_<", "T_T", "QAQ", "Orz", "♪", "♡"])
  }
  func testPunctuationCleanupMatchesAndroidAndPreservesParagraphs() {
    XCTAssertEqual(OutputRules.cleanSymbols("  你好  ，!?\r\n\r\n\r\n（ 测试 ）\t 好\u{00a0}呀  "), "你好？\n\n（测试） 好 呀")
    XCTAssertEqual(OutputRules.punctuation("你好 ,! 明天见?!", preference: "智能标点"), "你好！ 明天见？")
    XCTAssertEqual(OutputRules.punctuation("（ 测试 ）\n你好，明天见！", preference: "空格代替标点"), "测试\n你好 明天见")
  }
  func testThreeSuggestionsPreserveAndroidPromptTemperatureAndRawOutput() async throws {
    for relation: String? in [nil, "朋友"] {
      let transport = FixtureTransport("{\"choices\":[{\"message\":{\"content\":\"[\\\"你好！\\\",\\\"明天见。\\\",\\\"好呀～\\\"]\"}}]}")
      let api = APIClient(transport: transport)
      var settings = Settings()
      settings.endpoint = Endpoint()
      settings.endpoint?.url = "https://api.example.com/v1"
      settings.endpoint?.model = "test"
      settings.punctuation = "空格代替标点"
      settings.professional = [Word(term: "不会额外传入三条备选", hint: "")]
      let output = try await api.suggestions(text: "测试", relation: relation, settings: settings, key: "fixture", token: nil)
      XCTAssertEqual(output, ["你好！", "明天见。", "好呀～"])
      let request = await transport.last()!
      let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
      XCTAssertEqual(body["temperature"] as? Double, relation == nil ? 0.8 : 0.75)
      let messages = body["messages"] as! [[String: Any]]
      let system = messages[0]["content"] as! String
      XCTAssertFalse(system.contains("不会额外传入三条备选"))
      if relation == nil {
        XCTAssertEqual(system, settings.replyPrompt + "\n请针对对方消息生成3条语气和表达方式不同、均可直接发送的回复。只输出JSON字符串数组，必须正好3项，不要分析和解释。")
      } else {
        XCTAssertEqual(system, "你是恋爱沟通助手。用户面对的关系是：朋友。关系专属要求：\(settings.relationPrompts["朋友"]!) 请把用户想说的话改写成3条自然、真诚、语气有差异且可直接发送的话术。只输出JSON字符串数组，必须正好3项，不要解释。")
      }
    }
  }
}

extension ParityTests {
  func testStructuredVoiceListsMatchAndroidFallback() {
    let source = "今天要做三件事，第一睡觉，第二刷牙，第三洗澡"
    XCTAssertTrue(StructuredExpression.needsStructure(source))
    XCTAssertEqual(StructuredExpression.enforce(source: source, polished: source), "今天要做三件事：\n1.睡觉\n2.刷牙\n3.洗澡")
    let formatted = "待办：\n1.睡觉\n2.刷牙\n3.洗澡"
    XCTAssertEqual(StructuredExpression.enforce(source: source, polished: formatted), formatted)
    XCTAssertEqual(StructuredExpression.enforce(source: "包括：苹果、香蕉", polished: "包括：苹果、香蕉"), "包括：\n1.苹果\n2.香蕉")
    XCTAssertEqual(VoicePrompts.localFallback("那个，嗯，我 明天见！"), "我 明天见！")
  }
  func testVoiceTranslationUsesSameTextContractWithoutSendingAudio() async throws {
    let transport = FixtureTransport("{\"choices\":[{\"message\":{\"content\":\"See you tomorrow.\"}}]}")
    let api = APIClient(transport: transport)
    var settings = Settings()
    settings.endpoint = Endpoint()
    settings.endpoint?.url = "https://api.example.com/v1"
    settings.endpoint?.model = "test"
    let result = try await api.processVoice(text: "明天见", mode: "翻译", style: "聊天自然", settings: settings, key: "fixture", token: nil)
    XCTAssertEqual(result, "See you tomorrow.")
    let request = await transport.last()!
    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    let messages = body["messages"] as! [[String: Any]]
    XCTAssertEqual(messages[0]["content"] as? String, VoicePrompts.translation)
    XCTAssertEqual(messages[1]["content"] as? String, "明天见")
    XCTAssertEqual(body["temperature"] as? Double, 0.1)
    XCTAssertFalse(String(data: request.httpBody!, encoding: .utf8)!.contains("input_audio"))
  }
  func testDictationAndRawStyleNeedNoTextModel() async throws {
    let transport = FixtureTransport("{}"); let api = APIClient(transport: transport)
    let value = try await api.processVoice(text: "你好，世界！", mode: "听写", style: "聊天自然", settings: Settings(), key: nil, token: nil)
    XCTAssertEqual(value, "你好，世界！")
    let value2 = try await api.processVoice(text: "你好", mode: "润色", style: "不润色", settings: Settings(), key: nil, token: nil)
    XCTAssertEqual(value2, "你好")
    let request = await transport.last()
    XCTAssertNil(request)
  }
}

extension ParityTests {
  func testPredictionFrequencyBeatsRecencyAndNeverLearnsSensitiveText() {
    XCTAssertEqual(PredictionEngine.tokens("验证码123456"), ["验证码"])
    for secret in ["123456", "user@example.com", "https://example.com", "aB1234567890abcdef"] {
      XCTAssertTrue(PredictionEngine.tokens(secret).isEmpty)
    }
    XCTAssertEqual(PredictionEngine.suggestions(tokens: ["good"], base: nil, enhanced: nil, learned: []), ["morning", "afternoon", "evening"])
    let learned = [
      PredictionLearning(context: "hello", target: "often", useCount: 50, lastUsedAt: 1_000),
      PredictionLearning(context: "hello", target: "recent", useCount: 1, lastUsedAt: 2_000),
    ]
    XCTAssertEqual(PredictionEngine.suggestions(tokens: ["hello"], base: nil, enhanced: nil, learned: learned).prefix(2), ["often", "recent"])
    XCTAssertEqual(PredictionEngine.contexts(["thank", "you"]).first, "thank\u{001f}you")
    XCTAssertEqual(PredictionEngine.transitions(previous: ["thank"], appended: ["you"]).first?.0, "thank")
    XCTAssertTrue(PredictionEngine.appendSpace("world"))
    XCTAssertFalse(PredictionEngine.appendSpace("世界"))
  }
  func testCorruptPredictionPackIsRejected() {
    for data in [Data(), Data([0, 0, 0, 0]), Data([0x56, 0x54, 0x50, 0x31, 1, 0, 0, 0])] {
      XCTAssertThrowsError(try PredictionIndex(data: data))
    }
  }
}
