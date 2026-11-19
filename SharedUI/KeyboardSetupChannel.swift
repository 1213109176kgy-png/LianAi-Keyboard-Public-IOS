import Foundation
import LianAiCore

enum KeyboardSetupChannel {
  static func mailbox() -> KeyboardSetupMailbox? {
    guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Product.group) else { return nil }
    return KeyboardSetupMailbox(directory: group.appendingPathComponent("KeyboardSetup", isDirectory: true))
  }
}
