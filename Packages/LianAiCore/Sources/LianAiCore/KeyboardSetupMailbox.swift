import Foundation

/// A fresh challenge prevents a previous installation's receipt from completing setup.
/// Only an enabled keyboard with Full Access can write the shared response.
public struct KeyboardSetupMailbox: Sendable {
  public let directory: URL
  public init(directory: URL) { self.directory = directory }
  private var requestURL: URL { directory.appendingPathComponent("request.json") }
  private var receiptURL: URL { directory.appendingPathComponent("receipt.json") }
  public func request(_ challenge: UUID) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(challenge).write(to: requestURL, options: .atomic)
  }
  public func confirmFromKeyboard(hasFullAccess: Bool) throws {
    guard hasFullAccess,
      let data = try? Data(contentsOf: requestURL),
      let challenge = try? JSONDecoder().decode(UUID.self, from: data)
    else { return }
    try JSONEncoder().encode(challenge).write(to: receiptURL, options: .atomic)
  }
  public func isConfirmed(_ challenge: UUID) -> Bool {
    guard let data = try? Data(contentsOf: receiptURL),
      let receipt = try? JSONDecoder().decode(UUID.self, from: data)
    else { return false }
    return receipt == challenge
  }
}
