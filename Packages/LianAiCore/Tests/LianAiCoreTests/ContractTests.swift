import XCTest

@testable import LianAiCore

actor FixtureTransport: HTTPTransport {
  var requests: [URLRequest] = []
  let response: Data
  let status: Int
  init(_ text: String, status: Int = 200) {
    response = Data(text.utf8)
    self.status = status
  }
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    return (
      response,
      HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    )
  }
  func last() -> URLRequest? { requests.last }
}
@MainActor final class ContractTests: XCTestCase {
  func testOutputRulesKeepEnglishNullAndRemoveASRMarkup() {
    XCTAssertEqual(OutputRules.transcript("<chinese>你好</chinese>null"), "你好")
    XCTAssertEqual(
      OutputRules.transcript("<english>the value is null</english>"), "the value is null")
    XCTAssertEqual(OutputRules.punctuation("你好，明天见！", preference: "空格代替标点"), "你好 明天见")
    XCTAssertEqual(OutputRules.punctuation("你好，明天见！", preference: "句末不添加标点"), "你好，明天见")
  }
  func testThinkingControlsFollowAndroidModelAndDomainRules() {
    XCTAssertEqual(
      ThinkingPolicy.control(
        url: URL(string: "https://api.deepseek.com/v1")!, model: "deepseek-reasoner"), .required)
    XCTAssertEqual(
      ThinkingPolicy.control(
        url: URL(string: "https://open.bigmodel.cn/api/paas/v4")!, model: "glm-4.7"), .available)
    XCTAssertEqual(
      ThinkingPolicy.control(
        url: URL(string: "https://open.bigmodel.cn/api/paas/v4")!, model: "glm-5.3"), .required)
    XCTAssertEqual(
      ThinkingPolicy.control(
        url: URL(string: "https://dashscope.aliyuncs.com/v1")!, model: "qwen-plus"), .unsupported)
    XCTAssertEqual(
      ThinkingPolicy.control(
        url: URL(string: "https://api.xiaomimimo.com/v1")!, model: "mimo-v2.5-asr"), .unsupported)
  }
  func testMiMoASRUsesAndroidRequestContractAndCleansTags() async throws {
    let transport = FixtureTransport(
      "{\"choices\":[{\"message\":{\"content\":\"<chinese>你好</chinese>\"}}]}")
    let api = APIClient(transport: transport)
    let value = try await api.transcribe(wav: Data([0, 1]), asrKey: "test-key", token: nil)
    XCTAssertEqual(value, "你好")
    let req = await transport.last()!
    XCTAssertEqual(req.value(forHTTPHeaderField: "api-key"), "test-key")
    XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
    XCTAssertEqual(body["model"] as? String, "mimo-v2.5-asr")
    XCTAssertNil(body["temperature"])
    let messages = body["messages"] as! [[String: Any]]
    XCTAssertEqual(messages.count, 1)
  }
  func testASRWAVIsCanonicalMono16kAndRejectsInvalidPCM() throws {
    let pcm = Data(repeating: 0, count: 32000)
    let wav = try WAVEncoder.mono16k(pcm16: pcm)
    XCTAssertEqual(wav.count, pcm.count + 44)
    XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
    XCTAssertEqual(String(data: wav[36..<40], encoding: .ascii), "data")
    XCTAssertEqual(Array(wav[24..<28]), [0x80, 0x3e, 0, 0])
    XCTAssertEqual(wav.suffix(pcm.count), pcm)
    for invalid in [Data(), Data([1]), Data(repeating: 0, count: 2_880_002)] {
      XCTAssertThrowsError(try WAVEncoder.mono16k(pcm16: invalid))
    }
  }
  func testPaymentRejectsLookalikesCredentialsAndOtherSchemes() throws {
    for url in [
      "http://openapi.alipay.com/pay", "https://openapi.alipay.com.attacker.test/pay",
      "https://user@openapi.alipay.com/pay", "lianai://payment-return",
      "https://openapi.alipay.com:8443/pay", "https://evil.test/?to=https://openapi.alipay.com",
    ] { XCTAssertThrowsError(try PaymentPolicy.validatedPaymentURL(url)) }
    XCTAssertEqual(
      try PaymentPolicy.validatedPaymentURL("https://openapi.alipay.com/gateway.do?order=1").host,
      "openapi.alipay.com")
    XCTAssertTrue(PaymentPolicy.isReturn(URL(string: "lianai://payment-return?status=paid")!))
    XCTAssertFalse(PaymentPolicy.terminal("created"))
  }
  func testSuggestionsRequireThreeDistinctNonemptyValues() throws {
    XCTAssertEqual(
      try Suggestions.parse("```json\n[\"好呀\",\"我也期待\",\"一起试试\"]\n```"), ["好呀", "我也期待", "一起试试"])
    for value in ["[\"a\",\"a\",\"b\"]", "[\"\",\"a\",\"b\"]", "说明：这不是JSON", "[]"] {
      XCTAssertThrowsError(try Suggestions.parse(value))
    }
  }
  func testCandidateReplacementOnlyDeletesTrackedSuffixAtSameContext() {
    var tracker = InsertTracker()
    tracker.remember(text: "你好👨‍👩‍👧", before: "已有文字你好👨‍👩‍👧")
    XCTAssertEqual(tracker.replacementDeletionCount(before: "已有文字你好👨‍👩‍👧", selected: nil), 3)
    XCTAssertEqual(tracker.replacementDeletionCount(before: "别的文字你好👨‍👩‍👧", selected: nil), 0)
    XCTAssertEqual(tracker.replacementDeletionCount(before: "已有文字你好👨‍👩‍👧", selected: "你"), 0)
    XCTAssertEqual(tracker.replacementDeletionCount(before: nil, selected: nil), 0)
    tracker.invalidate()
    XCTAssertEqual(tracker.replacementDeletionCount(before: "已有文字你好👨‍👩‍👧", selected: nil), 0)
  }
  func testHistoryDefaultDoesNotRecordAndRetentionClears() {
    var settings = Settings()
    settings.record(kind: "听写", content: "测试")
    XCTAssertTrue(settings.history.isEmpty)
    settings.retention = "永久"
    settings.record(kind: "润色", content: "测试")
    XCTAssertEqual(settings.history.count, 1)
    settings.retention = "从不"
    settings.pruneHistory()
    XCTAssertTrue(settings.history.isEmpty)
    XCTAssertFalse(settings.clipboardHistory)
    XCTAssertEqual(settings.keyboardModes, ["键盘", "帮你回", "超会说"])
  }
  func testOrderRequestUsesAlipayAndStableIdempotencyID() async throws {
    let transport = FixtureTransport(
      "{\"orderId\":\"LA123\",\"status\":\"created\",\"payUrl\":\"https://openapi.alipay.com/gateway.do\",\"free\":false}"
    )
    let api = APIClient(transport: transport)
    _ = try await api.createOrder(planID: "month", requestID: "retry-1", token: "test-session")
    let req = await transport.last()!
    let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: String]
    XCTAssertEqual(body, ["planId": "month", "channel": "alipay", "requestId": "retry-1"])
    XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-session")
    XCTAssertEqual(req.url?.path, "/api/app/orders")
  }
  func testUntrustedReturnCannotCreateAnOrderOrGrantEntitlement() async throws {
    let transport = FixtureTransport("{\"status\":\"created\"}")
    let api = APIClient(transport: transport)
    _ = try await api.order(id: "LA123", token: "test-session")
    let req = await transport.last()!
    XCTAssertEqual(req.httpMethod, "GET")
    XCTAssertNil(req.httpBody)
    XCTAssertThrowsError(try Endpoint().validatedURL())
  }
  func testEndpointCatalogNormalizesChatCompletionsSuffix() throws {
    var e = Endpoint()
    e.url = "https://example.com/v1/chat/completions"
    XCTAssertEqual(
      try e.validatedURL(path: "models").absoluteString, "https://example.com/v1/models")
    e.url = "https://key@example.com/v1"
    XCTAssertThrowsError(try e.validatedURL())
  }
  func testServerErrorKeepsHTTPCodeForAccountAndPendingRecovery() async {
    let api = APIClient(transport: FixtureTransport("{\"message\":\"登录已过期\"}", status: 401))
    do {
      _ = try await api.order(id: "LA123", token: "test")
      XCTFail("Should fail")
    } catch ClientError.http(let code, let text) {
      XCTAssertEqual(code, 401)
      XCTAssertEqual(text, "登录已过期")
    } catch { XCTFail("Wrong error: \(error)") }
  }
}
