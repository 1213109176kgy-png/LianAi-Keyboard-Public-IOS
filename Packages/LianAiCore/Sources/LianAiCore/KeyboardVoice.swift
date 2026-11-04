import Foundation

public enum KeyboardVoicePhase: String, Codable, Sendable {
  case stopped, ready, listening, processing, result, failed
}
public struct KeyboardVoiceState: Codable, Equatable, Sendable {
  public var session: UUID
  public var request: UUID?
  public var phase: KeyboardVoicePhase
  public var text: String
  public var message: String
  public var updatedAt: Date
  public var startedAt: Date?
  public init(session: UUID = UUID(), request: UUID? = nil, phase: KeyboardVoicePhase = .stopped,
    text: String = "", message: String = "", updatedAt: Date = Date(), startedAt: Date? = nil) {
    self.session = session; self.request = request; self.phase = phase
    self.text = text; self.message = message; self.updatedAt = updatedAt; self.startedAt = startedAt
  }
  public func isLive(at now: Date = Date()) -> Bool {
    phase != .stopped && now.timeIntervalSince(updatedAt) >= -2 && now.timeIntervalSince(updatedAt) < 4
  }
}
public struct KeyboardVoiceCommand: Codable, Sendable {
  public enum Action: String, Codable, Sendable { case start, finish, cancel, acknowledge, keepAlive, stopSession }
  public var id: UUID
  public var session: UUID
  public var request: UUID
  public var action: Action
  public var createdAt: Date
  public init(session: UUID, request: UUID, action: Action, createdAt: Date = Date()) {
    id = UUID(); self.session = session; self.request = request; self.action = action; self.createdAt = createdAt
  }
}
/// Files are atomic and commands are queued, so a quick release cannot overwrite
/// an unconsumed start. No audio is written to the shared container.
public struct KeyboardVoiceMailbox: Sendable {
  public let directory: URL
  public init(directory: URL) throws {
    self.directory = directory
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  public func send(_ command: KeyboardVoiceCommand) throws {
    try JSONEncoder().encode(command).write(to: directory.appendingPathComponent(command.id.uuidString + ".command"), options: .atomic)
  }
  public func commands() throws -> [KeyboardVoiceCommand] {
    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "command" }
      .compactMap { try? JSONDecoder().decode(KeyboardVoiceCommand.self, from: Data(contentsOf: $0)) }
      .sorted { $0.createdAt < $1.createdAt }
  }
  public func remove(_ command: KeyboardVoiceCommand) {
    try? FileManager.default.removeItem(at: directory.appendingPathComponent(command.id.uuidString + ".command"))
  }
  public func write(_ state: KeyboardVoiceState) throws {
    try JSONEncoder().encode(state).write(to: directory.appendingPathComponent("state.json"), options: .atomic)
  }
  public func read() -> KeyboardVoiceState? {
    try? JSONDecoder().decode(KeyboardVoiceState.self, from: Data(contentsOf: directory.appendingPathComponent("state.json")))
  }
  public func clearCommands() throws { for command in try commands() { remove(command) } }
}
/// A transcript belongs to one focus position. Moving the caret, replacing a
/// selection, changing account/mode, or opening another field invalidates it.
public struct VoiceInsertionAnchor: Equatable, Sendable {
  public var document: UUID
  public var before: String?
  public var after: String?
  public var selected: String?
  public var mode: String
  public var draft: String
  public var cursor: Int
  public var account: String?
  public init(document: UUID, before: String?, after: String?, selected: String?, mode: String,
    draft: String = "", cursor: Int = 0, account: String? = nil) {
    self.document = document; self.before = before; self.after = after; self.selected = selected
    self.mode = mode; self.draft = draft; self.cursor = cursor; self.account = account
  }
}
