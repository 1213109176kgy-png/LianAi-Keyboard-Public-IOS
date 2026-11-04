import AVFAudio
import LianAiCore

/// The audio tap owns conversion; snapshots are synchronized with that tap.
nonisolated final class SpeechPCM: @unchecked Sendable {
  private let lock = NSLock()
  private var pcm = Data()
  private let converter: AVAudioConverter
  private let format: AVAudioFormat
  init(input: AVAudioFormat) throws {
    guard input.sampleRate > 0, input.channelCount > 0,
      let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
      let converter = AVAudioConverter(from: input, to: format)
    else { throw ClientError.message("无法初始化麦克风音频格式") }
    self.format = format
    self.converter = converter
  }
  func append(_ input: AVAudioPCMBuffer) {
    lock.lock()
    defer { lock.unlock() }
    guard pcm.count < 2_880_000 else { return }
    let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * 16000 / input.format.sampleRate) + 32)
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
    var supplied = false
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
      if supplied { status.pointee = .noDataNow; return nil }
      supplied = true
      status.pointee = .haveData
      return input
    }
    guard error == nil, let samples = output.int16ChannelData?[0] else { return }
    let bytes = min(Int(output.frameLength) * 2, 2_880_000 - pcm.count)
    pcm.append(Data(bytes: samples, count: bytes))
  }
  func finish() {
    lock.lock()
    defer { lock.unlock() }
    // AVAudioConverter retains a short resampler tail. Drain it at end of speech
    // so final phonemes are included; partial snapshots intentionally stay live.
    for _ in 0..<16 {
      guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { return }
      var error: NSError?
      let status = converter.convert(to: output, error: &error) { _, state in
        state.pointee = .endOfStream
        return nil
      }
      if let samples = output.int16ChannelData?[0], error == nil {
        let bytes = min(Int(output.frameLength) * 2, max(0, 2_880_000 - pcm.count))
        pcm.append(Data(bytes: samples, count: bytes))
      }
      if error != nil || status == .endOfStream || output.frameLength == 0 { return }
    }
  }
  func snapshot() throws -> Data {
    lock.lock()
    let value = pcm
    lock.unlock()
    return try WAVEncoder.mono16k(pcm16: value)
  }
}
