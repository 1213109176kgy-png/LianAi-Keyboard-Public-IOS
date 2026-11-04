import Foundation

/// The ASR endpoint accepts a canonical 44-byte PCM WAV header.
public enum WAVEncoder {
  public static func mono16k(pcm16: Data) throws -> Data {
    guard !pcm16.isEmpty, pcm16.count.isMultiple(of: 2), pcm16.count <= 16000 * 2 * 90 else {
      throw ClientError.message("请录制 90 秒以内的有效语音")
    }
    var data = Data()
    func ascii(_ value: String) { data.append(contentsOf: value.utf8) }
    func le<T: FixedWidthInteger>(_ value: T) {
      var value = value.littleEndian
      withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
    ascii("RIFF")
    le(UInt32(36 + pcm16.count))
    ascii("WAVEfmt ")
    le(UInt32(16))
    le(UInt16(1))
    le(UInt16(1))
    le(UInt32(16000))
    le(UInt32(32000))
    le(UInt16(2))
    le(UInt16(16))
    ascii("data")
    le(UInt32(pcm16.count))
    data.append(pcm16)
    return data
  }
}
