import Foundation
import LianAiCore
import SwiftUI

@MainActor
final class KeyboardSetupCoordinator: ObservableObject {
  @Published private(set) var isComplete: Bool
  @Published private(set) var error = ""
  private let defaults: UserDefaults
  private let mailbox: KeyboardSetupMailbox?
  private let challengeKey = "keyboard.setup.challenge.v1"
  private let completedKey = "keyboard.setup.completed.v1"
  private let waitingKey = "keyboard.setup.waitingForSettings.v1"
  private var challenge: UUID?
  private(set) var waitingForSettings = false

  init(defaults: UserDefaults = .standard, mailbox: KeyboardSetupMailbox? = KeyboardSetupChannel.mailbox()) {
    self.defaults = defaults
    self.mailbox = mailbox
    isComplete = defaults.bool(forKey: completedKey)
    challenge = defaults.string(forKey: challengeKey).flatMap(UUID.init(uuidString:))
    waitingForSettings = defaults.bool(forKey: waitingKey)
  }
  func prepare() {
    guard !isComplete else { return }
    if challenge == nil { challenge = UUID() }
    guard let challenge else { return }
    defaults.set(challenge.uuidString, forKey: challengeKey)
    do {
      guard let mailbox else { throw ClientError.message("暂时无法验证，请重新打开 App 后重试") }
      try mailbox.request(challenge)
      error = ""
      checkCompletion()
    } catch { self.error = "暂时无法验证，请重新打开 App 后重试" }
  }
  func checkCompletion() {
    guard !isComplete, let challenge, mailbox?.isConfirmed(challenge) == true else { return }
    defaults.set(true, forKey: completedKey)
    isComplete = true
    error = ""
  }
  func willOpenSettings() {
    // Recheck the permission after a settings visit; an earlier receipt must not suffice.
    if !isComplete { challenge = UUID(); prepare() }
    waitingForSettings = true
    defaults.set(true, forKey: waitingKey)
  }
  func didReturnFromSettings() -> Bool {
    checkCompletion()
    guard waitingForSettings else { return false }
    waitingForSettings = false
    defaults.removeObject(forKey: waitingKey)
    return true
  }
}
