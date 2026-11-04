import Foundation
import LianAiCore

@MainActor
enum KeyboardVoiceUITestSupport {
  static func capture() -> (any KeyboardVoiceCapture)? {
    #if DEBUG
    if ProcessInfo.processInfo.environment["LIANAI_NATIVE_VOICE_TEST"] == "cloud" {
      return AppleKeyboardVoiceCapture(api: APIClient(transport: NativeMicrophoneASRFixture()), credentials: { ("native-voice-fixture-key", nil) })
    }
    if let scenario = ProcessInfo.processInfo.environment["LIANAI_VOICE_UI_TEST"],
      ["success", "failure", "empty", "pending"].contains(scenario) {
      return VoiceUIFixtureCapture(scenario: scenario)
    }
    #endif
    return nil
  }
  static func bootstrap() async {
    #if DEBUG
    if ProcessInfo.processInfo.environment["LIANAI_VOICE_UI_TEST"] != nil, capture() != nil { await KeyboardVoiceService.shared.enable() }
    #endif
  }
}
#if DEBUG
/// Only replaces microphone/Apple Speech at their boundary. The real app service,
/// disk queue, extension gesture and focus validation still run in UI tests.
@MainActor
private final class VoiceUIFixtureCapture: KeyboardVoiceCapture {
  let scenario: String
  private var update: (@MainActor @Sendable (String, Bool) -> Void)?
  private var failure: (@MainActor @Sendable (String) -> Void)?
  private var completion: Task<Void, Never>?
  init(scenario: String) { self.scenario = scenario }
  func arm() async throws {}
  func begin(update: @escaping @MainActor @Sendable (String, Bool) -> Void,
    failure: @escaping @MainActor @Sendable (String) -> Void) throws {
    self.update = update; self.failure = failure
    if scenario == "success" || scenario == "pending" { update("明天一起吃饭", false) }
  }
  func finish() {
    completion = Task {
      do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
      if scenario == "failure" { failure?("测试识别服务暂不可用") }
      else if scenario == "success" { update?("明天一起吃饭。", true) }
      else if scenario == "empty" { update?("", true) }
    }
  }
  func cancelUtterance() { completion?.cancel(); completion = nil; update = nil; failure = nil }
  func disarm() { cancelUtterance() }
}

private actor NativeMicrophoneASRFixture: HTTPTransport {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    guard request.url?.host == "api.xiaomimimo.com", let body = request.httpBody,
      let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
      let messages = object["messages"] as? [[String: Any]],
      let content = messages.first?["content"] as? [[String: Any]],
      let audio = content.first?["input_audio"] as? [String: String],
      let encoded = audio["data"], encoded.hasPrefix("data:audio/wav;base64,"),
      let wav = Data(base64Encoded: String(encoded.dropFirst("data:audio/wav;base64,".count))),
      wav.count > 1000, String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF"
    else { throw ClientError.message("原生音频未产生有效 WAV") }
    try await Task.sleep(for: .milliseconds(300))
    let data = Data(#"{"choices":[{"message":{"content":"原生音频测试。"}}]}"#.utf8)
    return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
  }
}
#endif
