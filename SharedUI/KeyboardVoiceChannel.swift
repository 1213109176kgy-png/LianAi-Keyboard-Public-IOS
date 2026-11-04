import Foundation
import LianAiCore

enum KeyboardVoiceChannel {
  static func mailbox() -> KeyboardVoiceMailbox? {
    guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Product.group) else { return nil }
    return try? KeyboardVoiceMailbox(directory: group.appendingPathComponent("KeyboardVoice", isDirectory: true))
  }
}
