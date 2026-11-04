import Foundation
import LianAiCore
import UIKit

/// Deterministic service responses for isolated UI tests; no test transport or
/// test launch configuration exists in Release builds.
@MainActor
enum KeyboardUITestSupport {
  #if DEBUG
  private static let scenarioKey = "keyboard.uiTest.scenario"
  private static var scenario: String? {
    let defaults = UserDefaults(suiteName: Product.group)
    guard (defaults?.double(forKey: scenarioKey + ".expires") ?? 0) > Date().timeIntervalSince1970 else { return nil }
    return defaults?.string(forKey: scenarioKey)
  }
  static func bootstrap() {
    guard let scenario = ProcessInfo.processInfo.environment["LIANAI_AI_UI_TEST"],
      ["success", "failure", "timeout", "no_model", "slow", "long"].contains(scenario) else {
        UserDefaults(suiteName: Product.group)?.removeObject(forKey: scenarioKey)
        UserDefaults(suiteName: Product.group)?.removeObject(forKey: scenarioKey + ".expires")
        if SharedStore.shared.settings.endpoint?.url == "https://keyboard-ui-test.invalid/v1" {
          SharedStore.shared.settings.endpoint = nil
        }
        return
      }
    UserDefaults(suiteName: Product.group)?.set(scenario, forKey: scenarioKey)
    UserDefaults(suiteName: Product.group)?.set(Date().timeIntervalSince1970 + 300, forKey: scenarioKey + ".expires")
    UserDefaults(suiteName: Product.group)?.removeObject(forKey: "requestedDestination")
    let store = SharedStore.shared
    var settings = Settings()
    if scenario != "no_model" {
      var endpoint = Endpoint()
      endpoint.url = "https://keyboard-ui-test.invalid/v1"
      endpoint.model = "fixture-model"
      settings.endpoint = endpoint
    }
    store.settings = settings
    UIPasteboard.general.string = "明天一起吃饭吗？"
  }
  static func client() -> APIClient {
    guard let scenario else { return .shared }
    return APIClient(transport: KeyboardUIFixtureTransport(scenario: scenario))
  }
  static func modelKey() -> String? {
    scenario != nil ? "ui-fixture-key" : SecretStore.read(key: "modelKey")
  }
  #else
  static func bootstrap() {}
  static func client() -> APIClient { .shared }
  static func modelKey() -> String? { SecretStore.read(key: "modelKey") }
  #endif
}
#if DEBUG
private actor KeyboardUIFixtureTransport: HTTPTransport {
  let scenario: String
  init(scenario: String) { self.scenario = scenario }
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    guard request.url?.host == "keyboard-ui-test.invalid", request.httpMethod == "POST",
      let data = request.httpBody,
      let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let messages = body["messages"] as? [[String: Any]],
      messages.count == 2
    else { throw ClientError.message("UI fixture received an invalid AI request") }
    let vision = messages.last?["content"] as? [[String: Any]]
    if let vision {
      guard let image = vision.first?["image_url"] as? [String: String],
        let url = image["url"], url.hasPrefix("data:image/jpeg;base64,"),
        let bytes = Data(base64Encoded: String(url.dropFirst("data:image/jpeg;base64,".count))), bytes.count > 100
      else { throw ClientError.message("Invalid screenshot payload") }
    } else {
      guard let text = messages.last?["content"] as? String, !text.isEmpty else { throw ClientError.message("Empty AI source") }
    }
    try await Task.sleep(for: .milliseconds(scenario == "slow" ? 3000 : 350))
    if scenario == "timeout" { throw URLError(.timedOut) }
    let response: Data
    let status: Int
    if scenario == "failure" {
      status = 503
      response = Data(#"{"message":"测试服务暂不可用，请重试"}"#.utf8)
    } else {
      status = 200
      let system = messages[0]["content"] as? String ?? ""
      let title = system.contains("请针对对方消息") ? "回复" : "话术"
      let values = ["第一条" + title, "第二条" + title, "第三条" + title].map {
        scenario == "long" ? $0 + "：" + String(repeating: "谢谢你认真告诉我你的想法，我会好好考虑，也想听听你的建议。", count: 4) : $0
      }
      let payload: Any = vision == nil ? values : ["scenario": "朋友", "analysis": "测试截图识别", "replies": ["第一条截图回复", "第二条截图回复", "第三条截图回复"]]
      let content = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
      response = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
    }
    return (response, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
  }
}
#endif
