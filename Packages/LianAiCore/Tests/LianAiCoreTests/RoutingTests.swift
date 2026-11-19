import XCTest

@testable import LianAiCore

actor QueueTransport: HTTPTransport {
  private var replies: [(String, Int)]
  private var requests: [URLRequest] = []
  init(_ replies: [(String, Int)]) { self.replies = replies }
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    let next = replies.removeFirst()
    return (
      Data(next.0.utf8),
      HTTPURLResponse(url: request.url!, statusCode: next.1, httpVersion: nil, headerFields: nil)!
    )
  }
  func captured() -> [URLRequest] { requests }
}
@MainActor
final class RoutingTests: XCTestCase {
  private let chat = #"{"choices":[{"message":{"content":"[\"好呀\",\"明天见\",\"我很期待\"]"}}]}"#
  private func config(vip: Bool, version: Int = 1) -> String {
    let feature =
      #"{"enabled":true,"modelId":"official-model-id","model":"official-model","thinkingEnabled":false}"#
    return
      "{\"schemaVersion\":\(version),\"user\":{\"vip\":{\"active\":\(vip),\"expiresAt\":4102444800000}},\"features\":{\"replySuggestions\":\(feature),\"superSpeak\":\(feature),\"visionReply\":\(feature),\"speechRecognition\":\(feature)}}"
  }
  private var custom: Settings {
    var settings = Settings()
    var endpoint = Endpoint()
    endpoint.url = "https://example.com/v1"
    endpoint.model = "my-model"
    settings.endpoint = endpoint
    return settings
  }
  func testVIPUsesOfficialProxyAndSessionInsteadOfCustomKey() async throws {
    let transport = QueueTransport([(config(vip: true), 200), (chat, 200)])
    let api = APIClient(transport: transport)
    let replies = try await api.suggestions(
      text: "明天见", relation: nil, settings: custom, key: "custom-key", token: "user-session")
    XCTAssertEqual(replies.count, 3)
    let requests = await transport.captured()
    XCTAssertEqual(requests.last?.url?.path, "/api/app/text/reply/chat/completions")
    XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer user-session")
    let body = try JSONSerialization.jsonObject(with: requests.last!.httpBody!) as! [String: Any]
    XCTAssertEqual(body["model"] as? String, "official-model")
  }
  func testNonVIPCanUseCustomEndpointAfterConfigRefresh() async throws {
    let transport = QueueTransport([(config(vip: false), 200), (chat, 200)])
    let api = APIClient(transport: transport)
    _ = try await api.suggestions(
      text: "明天见", relation: "朋友", settings: custom, key: "custom-key", token: "user-session")
    let requests = await transport.captured()
    XCTAssertEqual(requests.map { $0.url!.path }, ["/api/app/config", "/v1/chat/completions"])
    XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer custom-key")
  }
  func testCustomEndpointWorksWithoutAccount() async throws {
    let transport = QueueTransport([(chat, 200)])
    _ = try await APIClient(transport: transport).suggestions(
      text: "明天见", relation: nil, settings: custom, key: "custom-key", token: nil)
    let requests = await transport.captured()
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(requests.first?.url?.host, "example.com")
  }
  func testSelectedKnowledgeTravelsAsReferenceDataWithOriginalSource() async throws {
    let transport = QueueTransport([(chat, 200)])
    let reference = AIKnowledge.goutoujunshi.reference(for: "明天一起吃饭")
    _ = try await APIClient(transport: transport).suggestions(
      text: "明天一起吃饭", relation: "朋友", settings: custom, key: "fixture-key", token: nil,
      reference: reference)
    let request = await transport.captured().last!
    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    let messages = body["messages"] as! [[String: String]]
    XCTAssertTrue(messages[0]["content"]!.contains("不改变要求的JSON输出格式"))
    XCTAssertTrue(messages[1]["content"]!.hasPrefix("用户原话：\n明天一起吃饭\n"))
    XCTAssertTrue(messages[1]["content"]!.contains(reference))
  }
  func testExpiredLoginCannotSilentlySwitchToAnotherCredential() async {
    let transport = QueueTransport([(#"{"message":"登录已过期"}"#, 401)])
    do {
      _ = try await APIClient(transport: transport).suggestions(
        text: "明天见", relation: nil, settings: custom, key: "custom-key", token: "expired")
      XCTFail("Expected expired-session error")
    } catch ClientError.http(let code, _) { XCTAssertEqual(code, 401) } catch {
      XCTFail("Unexpected error: \(error)")
    }
    let requests = await transport.captured()
    XCTAssertEqual(requests.count, 1)
  }
  func testUnknownRuntimeConfigVersionIsRejected() async {
    let api = APIClient(transport: QueueTransport([(config(vip: true, version: 2), 200)]))
    do {
      _ = try await api.config(token: "session")
      XCTFail("Expected unsupported version")
    } catch { XCTAssertEqual(error.localizedDescription, "App 配置版本不支持，请升级 App") }
  }
  func testVisionProxyReceivesOnlyExplicitImageAndReturnsThreeChoices() async throws {
    let vision = #"{"scenario":"朋友","analysis":"相约见面","replies":["好呀","明天见","我很期待"]}"#
    let transport = QueueTransport([(config(vip: true), 200), (vision, 200)])
    let result = try await APIClient(transport: transport).vision(
      image: Data([1, 2, 3]), settings: Settings(), key: nil, token: "session")
    XCTAssertEqual(result.replies.count, 3)
    let request = await transport.captured().last!
    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
    XCTAssertEqual(body, ["imageBase64": "AQID", "mime": "image/jpeg"])
    XCTAssertEqual(request.url?.path, "/api/app/vision/reply")
  }
}

extension RoutingTests {
  func testVIPDisabledFeatureShowsBindingGuideWithoutPurchasingAgain() async {
    let disabled = config(vip: true).replacingOccurrences(of: "\"enabled\":true", with: "\"enabled\":false")
    let api = APIClient(transport: QueueTransport([(disabled, 200)]))
    do {
      _ = try await api.suggestions(text: "测试", relation: nil, settings: Settings(), key: nil, token: "session")
      XCTFail("Expected configuration guide")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("该功能尚未配置官方模型"))
      XCTAssertFalse(error.localizedDescription.contains("请开通 VIP"))
    }
  }
  func testEnabledOfficialFeatureDoesNotRequireOptionalModelID() async throws {
    let withoutID = config(vip: true).replacingOccurrences(of: "\"modelId\":\"official-model-id\",", with: "")
    let transport = QueueTransport([(withoutID, 200), (chat, 200)])
    let api = APIClient(transport: transport)
    _ = try await api.suggestions(text: "测试", relation: nil, settings: Settings(), key: nil, token: "session")
    let request = await transport.captured().last
    XCTAssertEqual(request?.url?.path, "/api/app/text/reply/chat/completions")
  }
}

extension RoutingTests {
  func testExpiredVIPUsesCustomRouteEvenIfCachedActiveFlagIsTrue() async throws {
    let expired = config(vip: true).replacingOccurrences(of: "4102444800000", with: "1")
    let transport = QueueTransport([(expired, 200), (chat, 200)])
    _ = try await APIClient(transport: transport).suggestions(text: "测试", relation: nil, settings: custom, key: "fixture", token: "session")
    let request = await transport.captured().last
    XCTAssertEqual(request?.url?.host, "example.com")
  }
}
