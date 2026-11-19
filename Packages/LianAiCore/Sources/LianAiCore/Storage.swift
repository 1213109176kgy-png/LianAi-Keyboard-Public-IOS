import Combine
import Foundation
import Security

@MainActor
public protocol CredentialVault {
  func read(key: String) -> String?
  func write(_ value: String, key: String) throws
}
@MainActor
public struct KeychainVault: CredentialVault {
  public init() {}
  public func read(key: String) -> String? { SecretStore.read(key: key) }
  public func write(_ value: String, key: String) throws { try SecretStore.write(value, key: key) }
}
@MainActor
public final class SharedStore: ObservableObject {
  public static let shared = SharedStore()
  private let defaults: UserDefaults
  private let vault: any CredentialVault
  private var readingSnapshot = false
  @Published public var settings: Settings {
    didSet { if !readingSnapshot { persist(settings, key: "settings.v1") } }
  }
  @Published public private(set) var user: User?
  public init(defaults: UserDefaults? = nil, vault: any CredentialVault = KeychainVault()) {
    self.vault = vault
    self.defaults = defaults ?? UserDefaults(suiteName: Product.group) ?? .standard
    settings = Self.read(Settings.self, key: "settings.v1", defaults: self.defaults) ?? Settings()
    user = Self.read(User.self, key: "user.v1", defaults: self.defaults)
    settings.pruneHistory()
  }
  private static func read<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T?
  { defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) } }
  private func persist<T: Encodable>(_ value: T, key: String) {
    if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
  }
  public func reload(persistPruned: Bool = false) {
    readingSnapshot = true
    settings = Self.read(Settings.self, key: "settings.v1", defaults: defaults) ?? settings
    settings.pruneHistory()
    user = Self.read(User.self, key: "user.v1", defaults: defaults)
    readingSnapshot = false
    if persistPruned { persist(settings, key: "settings.v1") }
  }
  /// Voice focus guards only need account identity. Avoid decoding large word
  /// dictionaries and publishing settings on each voice status poll.
  public func reloadUser() {
    let snapshot = Self.read(User.self, key: "user.v1", defaults: defaults)
    if user != snapshot { user = snapshot }
  }
  public func saveSession(_ session: Session) throws {
    try vault.write(session.token, key: "token")
    if user?.id != session.user.id {
      pending = nil
      prepared = nil
    }
    user = session.user
    persist(session.user, key: "user.v1")
  }
  public func token() -> String? {
    // Keychain credentials may outlive an installation. A surviving token alone
    // must not authenticate an app whose account snapshot says it is logged out.
    guard user != nil, let token = vault.read(key: "token"), !token.isEmpty else { return nil }
    return token
  }
  public func logout() throws {
    try vault.write("", key: "token")
    user = nil
    defaults.removeObject(forKey: "user.v1")
    pending = nil
    prepared = nil
  }
  public var pending: PendingPurchase? {
    get {
      let p = Self.read(PendingPurchase.self, key: "pending.v1", defaults: defaults)
      return p?.userID == user?.id ? p : nil
    }
    set {
      if let newValue {
        persist(newValue, key: "pending.v1")
      } else {
        defaults.removeObject(forKey: "pending.v1")
      }
      objectWillChange.send()
    }
  }
  public var prepared: PreparedResult? {
    get {
      Self.read(PreparedResult.self, key: "prepared.v1", defaults: defaults).flatMap {
        $0.isValid(userID: user?.id) ? $0 : nil
      }
    }
    set {
      if let newValue {
        persist(newValue, key: "prepared.v1")
      } else {
        defaults.removeObject(forKey: "prepared.v1")
      }
      objectWillChange.send()
    }
  }
}
public enum SecretStore {
  private static func query(_ key: String) -> [String: Any] {
    var q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.lianai.keyboard", kSecAttrAccount as String: key,
    ]
    if let group = Bundle.main.object(forInfoDictionaryKey: "SharedKeychainGroup") as? String,
      !group.contains("$("), !group.isEmpty
    {
      q[kSecAttrAccessGroup as String] = group
    }
    return q
  }
  public static func read(key: String) -> String? {
    var q = query(key)
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }
  public static func write(_ value: String, key: String) throws {
    let q = query(key)
    if value.isEmpty {
      let status = SecItemDelete(q as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw ClientError.message("无法清除安全存储（\(status)）")
      }
      return
    }
    let attrs: [String: Any] = [
      kSecValueData as String: Data(value.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    var status = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
    if status == errSecItemNotFound {
      status = SecItemAdd(q.merging(attrs) { _, new in new } as CFDictionary, nil)
    }
    guard status == errSecSuccess else {
      throw ClientError.message("安全存储失败（\(status)），请检查应用签名与 Keychain 权限")
    }
  }
}
