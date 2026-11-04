import AVFAudio
import LianAiCore
import Speech
import UIKit

/// The audio engine remains open for an explicitly enabled voice session. Idle
/// buffers are discarded in the tap; only an active utterance reaches Speech.
nonisolated final class VoiceAudioGate: @unchecked Sendable {
  private let lock = NSLock()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var pcm: SpeechPCM?
  func use(_ request: SFSpeechAudioBufferRecognitionRequest?, pcm: SpeechPCM? = nil) {
    lock.lock(); defer { lock.unlock() }; self.request = request; self.pcm = pcm
  }
  func append(_ buffer: AVAudioPCMBuffer) {
    lock.lock(); defer { lock.unlock() }
    request?.append(buffer)
    pcm?.append(buffer)
  }
}
@MainActor
protocol KeyboardVoiceCapture: AnyObject {
  var finalizationTimeout: TimeInterval { get }
  func arm() async throws
  func begin(update: @escaping @MainActor @Sendable (String, Bool) -> Void,
    failure: @escaping @MainActor @Sendable (String) -> Void) throws
  func finish()
  func cancelUtterance()
  func disarm()
}
@MainActor
extension KeyboardVoiceCapture { var finalizationTimeout: TimeInterval { 6 } }
@MainActor
final class AppleKeyboardVoiceCapture: KeyboardVoiceCapture {
  private var engine: AVAudioEngine?
  private let gate = VoiceAudioGate()
  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var pcm: SpeechPCM?
  private var format: AVAudioFormat?
  private var network: Task<Void, Never>?
  private var partial: Task<Void, Never>?
  private var ticket = UUID()
  private let api: APIClient
  private let credentials: @MainActor () -> (String?, String?)
  private var asrKey: String?
  private var token: String?
  private var update: (@MainActor @Sendable (String, Bool) -> Void)?
  private var failure: (@MainActor @Sendable (String) -> Void)?
  private var cloud: Bool { asrKey?.isEmpty == false || token?.isEmpty == false }
  var finalizationTimeout: TimeInterval { cloud ? 30 : 6 }
  init(api: APIClient = .shared, credentials: @escaping @MainActor () -> (String?, String?) = {
    (SecretStore.read(key: "asrKey"), SharedStore.shared.token())
  }) { self.api = api; self.credentials = credentials }
  func arm() async throws {
    guard UIApplication.shared.applicationState == .active else {
      throw ClientError.message("请在主 App 前台开启语音会话，然后返回聊天")
    }
    guard await AVAudioApplication.requestRecordPermission() else {
      throw ClientError.message("请在系统设置中允许恋爱键盘使用麦克风")
    }
    (asrKey, token) = credentials()
    if !cloud {
      let authorization = await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { @Sendable status in continuation.resume(returning: status) }
      }
      guard authorization == .authorized else {
        throw ClientError.message("请在系统设置中允许恋爱键盘使用语音识别，或配置语音接口")
      }
    }
    for _ in 0..<20 {
      if UIApplication.shared.applicationState == .active { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    guard UIApplication.shared.applicationState == .active else { throw CancellationError() }
    if !cloud {
      guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), recognizer.isAvailable else {
        throw ClientError.message("中文语音识别暂不可用，请检查网络或配置语音接口")
      }
      self.recognizer = recognizer
    }
    let audio = AVAudioSession.sharedInstance()
    try audio.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP])
    try audio.setActive(true)
    do {
      let engine = AVAudioEngine()
      let input = engine.inputNode
      let format = input.outputFormat(forBus: 0)
      self.format = format
      guard format.sampleRate > 0, format.channelCount > 0 else { throw ClientError.message("麦克风不可用，请检查音频设备") }
      let gate = self.gate
      input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in gate.append(buffer) }
      self.engine = engine
      engine.prepare()
      try engine.start()
    } catch { disarm(); throw error }
  }
  func begin(update: @escaping @MainActor @Sendable (String, Bool) -> Void,
    failure: @escaping @MainActor @Sendable (String) -> Void) throws {
    cancelUtterance()
    guard engine?.isRunning == true else {
      throw ClientError.message("语音会话已中断，请回到主 App 重新开启")
    }
    self.update = update; self.failure = failure
    if cloud {
      guard let format else { throw ClientError.message("麦克风音频格式不可用") }
      let capture = try SpeechPCM(input: format)
      pcm = capture; gate.use(nil, pcm: capture)
      let id = ticket
      partial = Task { [weak self] in
        while !Task.isCancelled {
          do { try await Task.sleep(for: .milliseconds(1400)) } catch { return }
          guard let self, self.ticket == id else { return }
          do {
            let wav = try capture.snapshot()
            guard wav.count > 44 else { continue }
            let text = try await self.api.transcribe(wav: wav, asrKey: self.asrKey, token: self.token)
            guard !Task.isCancelled, self.ticket == id else { return }
            self.update?(text, false)
          } catch is CancellationError { return } catch { /* final request reports errors */ }
        }
      }
      return
    }
    guard let recognizer, recognizer.isAvailable else { throw ClientError.message("系统语音识别暂不可用，请稍后重试") }
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.addsPunctuation = true
    // Prefer on-device recognition. Apple Speech may use its network service
    // on devices without an installed Chinese model; setup explains this.
    request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
    self.request = request
    task = recognizer.recognitionTask(with: request) { @Sendable result, error in
      let text = result?.bestTranscription.formattedString
      let final = result?.isFinal ?? false
      let message = error?.localizedDescription
      Task { @MainActor in
        if let text { update(text, final) }
        if let message {
          failure(message.contains("Failed to initialize recognizer")
            ? "系统中文语音识别未就绪，请联网重试，或在 App 配置语音接口" : message)
        }
      }
    }
    gate.use(request)
  }
  func finish() {
    gate.use(nil)
    if cloud {
      partial?.cancel(); partial = nil
      guard let pcm else { failure?("没有采集到语音"); return }
      pcm.finish(); self.pcm = nil
      let id = ticket
      do {
        let wav = try pcm.snapshot()
        guard wav.count > 44 else { failure?("没有采集到语音，请重试"); return }
        network = Task { [weak self] in
          guard let self else { return }
          do {
            let text = try await self.api.transcribe(wav: wav, asrKey: self.asrKey, token: self.token)
            guard !Task.isCancelled, self.ticket == id else { return }
            self.update?(text, true)
          } catch is CancellationError {} catch {
            guard self.ticket == id else { return }; self.failure?(error.localizedDescription)
          }
        }
      } catch { failure?(error.localizedDescription) }
    } else { request?.endAudio() }
  }
  func cancelUtterance() {
    ticket = UUID(); gate.use(nil); task?.cancel(); task = nil; request = nil
    network?.cancel(); network = nil; partial?.cancel(); partial = nil; pcm = nil
    update = nil; failure = nil
  }
  func disarm() {
    cancelUtterance()
    engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
@MainActor
final class KeyboardVoiceService: ObservableObject {
  static let shared = KeyboardVoiceService(capture: KeyboardVoiceUITestSupport.capture())
  @Published private(set) var state = KeyboardVoiceState()
  @Published private(set) var enabling = false
  private let mailbox: KeyboardVoiceMailbox?
  private let capture: any KeyboardVoiceCapture
  private var armed = false
  private var poll: Task<Void, Never>?
  private var finalize: Task<Void, Never>?
  private var lastKeyboardHeartbeat = Date()
  private var operation = UUID()
  private var observers: [NSObjectProtocol] = []
  init(mailbox: KeyboardVoiceMailbox? = KeyboardVoiceChannel.mailbox(), capture: (any KeyboardVoiceCapture)? = nil) {
    self.mailbox = mailbox; self.capture = capture ?? AppleKeyboardVoiceCapture()
    for name in [AVAudioSession.interruptionNotification, AVAudioSession.mediaServicesWereResetNotification,
      AVAudioSession.routeChangeNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
        if name == AVAudioSession.interruptionNotification,
          (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) != AVAudioSession.InterruptionType.began.rawValue { return }
        if name == AVAudioSession.routeChangeNotification {
          let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
          guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            || reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue else { return }
        }
        Task { @MainActor [weak self] in
          guard let self, self.armed else { return }
          self.stop(message: "音频会话已中断，请在主 App 重新开启")
        }
      })
    }
  }
  func enable() async {
    guard !enabling, !armed else { return }
    guard let mailbox else { state.message = "无法访问共享容器，请重新安装并启用键盘"; return }
    enabling = true
    operation = UUID(); let ticket = operation
    do {
      try await capture.arm()
      guard operation == ticket else { capture.disarm(); enabling = false; return }
      try mailbox.clearCommands()
      armed = true; enabling = false
      state = KeyboardVoiceState(phase: .ready, message: "语音已就绪，返回聊天后长按空格即可说话")
      publish()
      poll = Task { [weak self] in
        while !Task.isCancelled {
          guard let self else { return }
          self.tick()
          do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
        }
      }
    } catch {
      guard operation == ticket else { enabling = false; return }
      capture.disarm(); enabling = false
      state = KeyboardVoiceState(phase: .stopped, message: error.localizedDescription); publish()
    }
  }
  func stop(message: String = "语音会话已关闭") {
    operation = UUID(); finalize?.cancel(); finalize = nil; poll?.cancel(); poll = nil
    armed = false; enabling = false; capture.disarm()
    state = KeyboardVoiceState(phase: .stopped, message: message); publish()
    try? mailbox?.clearCommands()
  }
  func tick(now: Date = Date()) {
    guard armed else { return }
    do {
      if let mailbox {
        for command in try mailbox.commands() {
          mailbox.remove(command)
          handle(command, now: now)
        }
      }
    } catch { stop(message: "语音通信失败，请重新开启会话"); return }
    if [.listening, .processing].contains(state.phase), now.timeIntervalSince(lastKeyboardHeartbeat) > 4 {
      reset(); return
    }
    if state.phase == .listening, let start = state.startedAt, now.timeIntervalSince(start) >= 60 {
      finish()
    }
    if now.timeIntervalSince(state.updatedAt) >= 0.5 { publish(now: now) }
  }
  private func handle(_ command: KeyboardVoiceCommand, now: Date) {
    guard command.session == state.session, abs(now.timeIntervalSince(command.createdAt)) < 5 else { return }
    switch command.action {
    case .stopSession: stop()
    case .start:
      guard [.ready, .failed, .result].contains(state.phase) else { return }
      finalize?.cancel(); capture.cancelUtterance()
      lastKeyboardHeartbeat = now
      state.request = command.request; state.phase = .listening; state.text = ""; state.message = "正在听，请说话"; state.startedAt = now
      let id = command.request
      do {
        try capture.begin { [weak self] text, final in
          guard let self, self.state.request == id, [.listening, .processing].contains(self.state.phase) else { return }
          self.state.text = text
          if final { self.complete() } else { self.publish() }
        } failure: { [weak self] message in
          guard let self, self.state.request == id, [.listening, .processing].contains(self.state.phase) else { return }
          if self.state.phase == .processing && !self.state.text.isEmpty { self.complete() }
          else { self.fail("语音识别失败：" + message) }
        }
        publish(now: now)
      } catch { fail(error.localizedDescription) }
    case .keepAlive:
      if state.request == command.request { lastKeyboardHeartbeat = now }
    case .finish:
      guard state.request == command.request, state.phase == .listening else { return }
      finish()
    case .cancel, .acknowledge:
      guard state.request == command.request else { return }
      reset()
    }
  }
  private func finish() {
    state.phase = .processing; state.message = "正在识别…"; publish()
    capture.finish()
    let id = state.request
    finalize?.cancel()
    finalize = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(self?.capture.finalizationTimeout ?? 6)) } catch { return }
      guard let self, self.state.request == id, self.state.phase == .processing else { return }
      if self.state.text.isEmpty { self.fail("没有识别到语音，请重试") } else { self.complete() }
    }
  }
  private func complete() {
    finalize?.cancel(); finalize = nil; capture.cancelUtterance()
    state.text = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !state.text.isEmpty else { fail("没有识别到语音，请重试"); return }
    state.phase = .result; state.message = "识别完成"; publish()
  }
  private func fail(_ message: String) {
    finalize?.cancel(); finalize = nil; capture.cancelUtterance()
    state.phase = .failed; state.message = message; publish()
  }
  private func reset() {
    finalize?.cancel(); finalize = nil; capture.cancelUtterance()
    state.request = nil; state.phase = .ready; state.text = ""; state.startedAt = nil
    state.message = "语音已就绪"; publish()
  }
  private func publish(now: Date = Date()) {
    state.updatedAt = now
    do { try mailbox?.write(state) } catch {
      armed = false; capture.disarm(); poll?.cancel()
      state.phase = .stopped; state.message = "语音共享状态无法写入，请重新开启"
    }
  }
}
