import AVFAudio
import LianAiCore
import XCTest
@testable import LianAiKeyboard

@MainActor
final class AudioCaptureTests: XCTestCase {
  func testHardwareRateStereoIsConvertedToCanonicalASRMono16k() throws {
    let input = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 48000))
    buffer.frameLength = 48000
    for channel in 0..<2 {
      for index in 0..<48000 { buffer.floatChannelData![channel][index] = 0.25 }
    }
    let capture = try SpeechPCM(input: input)
    capture.append(buffer)
    let wav = try capture.snapshot()
    XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
    XCTAssertEqual(Array(wav[24..<28]), [0x80, 0x3e, 0, 0])
    XCTAssertEqual(Array(wav[22..<24]), [1, 0])
    XCTAssertTrue((29_000...32_100).contains(wav.count), "Live snapshots may retain the resampler tail: \(wav.count) bytes")
    capture.finish()
    XCTAssertTrue((31_980...32_108).contains(try capture.snapshot().count), "Final capture must drain the converter tail")
    XCTAssertTrue(wav.dropFirst(44).contains { $0 != 0 })
    let longCapture = try SpeechPCM(input: input)
    for _ in 0..<95 { longCapture.append(buffer) }
    longCapture.finish()
    XCTAssertEqual(try longCapture.snapshot().count, 2_880_044, "Capture must stop growing at 90 seconds")
  }
}
