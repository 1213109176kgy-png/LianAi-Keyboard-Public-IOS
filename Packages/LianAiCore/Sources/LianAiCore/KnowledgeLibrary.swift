import Foundation
import CoreFoundation

public struct KnowledgeDocument: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var title: String
  public var body: String
  public var enabled: Bool
  public var updatedAt: Date
  public var isSystem: Bool { AIKnowledge.allCases.contains { $0.documentID == id } }
  public init(id: String = UUID().uuidString, title: String, body: String, enabled: Bool = true) {
    self.id = id; self.title = title; self.body = body; self.enabled = enabled; updatedAt = Date()
  }
}
public struct KnowledgeState: Codable, Equatable, Sendable {
  public var documents: [KnowledgeDocument]
  public var defaultDocumentID: String?
  public var selectedDocumentID: String?
  public var revision: String
  var systemRevisions: [String: Int]
  public var selectedDocument: KnowledgeDocument? {
    documents.first { $0.id == selectedDocumentID && $0.enabled }
  }
  public var selectedTitle: String { selectedDocument?.title ?? "未选择知识库" }
  public func matching(_ query: String) -> [KnowledgeDocument] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return documents.filter { needle.isEmpty || $0.title.localizedCaseInsensitiveContains(needle) || $0.body.localizedCaseInsensitiveContains(needle) }
  }
}
public struct KnowledgeSnapshot: Sendable {
  public let revision: String
  public let document: KnowledgeDocument?
  public func reference(for query: String) -> String {
    guard let document else { return "" }
    return AIKnowledge.reference(title: document.title, body: document.body, query: query)
  }
}

/// One atomically replaced file in the App Group, shared by the app and keyboard.
/// Reads fail explicitly on corrupt data so a subsequent save cannot erase it.
@MainActor
public final class KnowledgeLibrary {
  public static let shared = KnowledgeLibrary()
  private let directory: URL
  private let defaults: UserDefaults
  public var fileURL: URL { directory.appendingPathComponent("knowledge.v1.json") }
  public init(directory: URL? = nil, defaults: UserDefaults? = nil) {
    self.defaults = defaults ?? UserDefaults(suiteName: Product.group) ?? .standard
    self.directory = directory ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Product.group)
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LianAiKnowledge")
  }
  public func read() throws -> KnowledgeState {
    var state: KnowledgeState
    let exists = FileManager.default.fileExists(atPath: fileURL.path)
    if exists {
      state = try JSONDecoder().decode(KnowledgeState.self, from: Data(contentsOf: fileURL))
    } else {
      let legacy = AIKnowledge(rawValue: defaults.string(forKey: "ai.knowledge") ?? "") ?? .goutoujunshi
      state = KnowledgeState(documents: [], defaultDocumentID: AIKnowledge.goutoujunshi.documentID,
        selectedDocumentID: legacy.documentID, revision: UUID().uuidString, systemRevisions: [:])
    }
    var changed = false
    for (index, builtin) in [AIKnowledge.goutoujunshi, .tongJincheng].enumerated() {
      let id = builtin.documentID!
      let revision = builtin == .goutoujunshi ? 3 : 1
      if state.documents.contains(where: { $0.id == id }), state.systemRevisions[id] == revision { continue }
      let enabled = state.documents.first { $0.id == id }?.enabled ?? true
      state.documents.removeAll { $0.id == id }
      state.documents.insert(KnowledgeDocument(id: id, title: builtin.title, body: try builtin.bundledBody(), enabled: enabled), at: min(index, state.documents.count))
      state.systemRevisions[id] = revision
      changed = true
    }
    if state.selectedDocumentID != nil && state.selectedDocument == nil { state.selectedDocumentID = nil; changed = true }
    if let id = state.defaultDocumentID, !state.documents.contains(where: { $0.id == id }) {
      state.defaultDocumentID = nil; changed = true
    }
    if changed || !exists { try write(&state) }
    return state
  }
  private func write(_ state: inout KnowledgeState) throws {
    state.revision = UUID().uuidString
    let data = try JSONEncoder().encode(state)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try data.write(to: fileURL, options: .atomic)
  }
  public func save(_ document: KnowledgeDocument) throws {
    guard !document.isSystem else { throw ClientError.message("系统知识库仅支持查看和启用/停用") }
    let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty && title.utf16.count <= 120 else { throw ClientError.message("请输入1–120字标题") }
    guard !document.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      document.body.utf16.count <= 300_000, !document.body.contains("\0") else {
      throw ClientError.message("请输入正文（最多30万字）")
    }
    var state = try read()
    var saved = document; saved.title = title; saved.updatedAt = Date()
    state.documents.removeAll { $0.id == saved.id }; state.documents.append(saved)
    if !saved.enabled && state.selectedDocumentID == saved.id { state.selectedDocumentID = nil }
    try write(&state)
  }
  public func setEnabled(_ id: String, _ enabled: Bool) throws {
    var state = try read()
    guard let index = state.documents.firstIndex(where: { $0.id == id }) else { throw ClientError.message("知识库不存在") }
    state.documents[index].enabled = enabled
    if !enabled && state.selectedDocumentID == id { state.selectedDocumentID = nil }
    try write(&state)
  }
  public func setDefault(_ id: String) throws {
    var state = try read()
    guard let index = state.documents.firstIndex(where: { $0.id == id }) else { throw ClientError.message("知识库不存在") }
    state.documents[index].enabled = true
    state.defaultDocumentID = id; state.selectedDocumentID = id
    try write(&state)
  }
  public func select(_ id: String?) throws {
    var state = try read()
    if let id, !state.documents.contains(where: { $0.id == id && $0.enabled }) { throw ClientError.message("知识库不存在或已停用") }
    state.selectedDocumentID = id
    try write(&state)
  }
  public func remove(_ id: String) throws {
    var state = try read()
    guard let document = state.documents.first(where: { $0.id == id }) else { throw ClientError.message("知识库不存在") }
    guard !document.isSystem else { throw ClientError.message("系统知识库不可删除") }
    state.documents.removeAll { $0.id == id }
    if state.selectedDocumentID == id { state.selectedDocumentID = nil }
    if state.defaultDocumentID == id { state.defaultDocumentID = nil }
    try write(&state)
  }
  public func snapshot() throws -> KnowledgeSnapshot {
    let state = try read()
    return KnowledgeSnapshot(revision: state.revision, document: state.selectedDocument)
  }
  public func isCurrent(_ snapshot: KnowledgeSnapshot) -> Bool {
    (try? read().revision) == snapshot.revision
  }
}

public struct ImportedKnowledge: Sendable {
  public let title: String
  public let body: String
}
public enum KnowledgeImport {
  public static func decode(_ data: Data, filename: String) throws -> ImportedKnowledge {
    guard ["txt", "md"].contains((filename as NSString).pathExtension.lowercased()) else {
      throw ClientError.message("首版仅支持 TXT、MD 文件")
    }
    guard data.count <= 1_048_576 else { throw ClientError.message("请选择 1MB 以内的资料") }
    let encoding: String.Encoding
    if data.starts(with: [0xff, 0xfe]) { encoding = .utf16LittleEndian }
    else if data.starts(with: [0xfe, 0xff]) { encoding = .utf16BigEndian }
    else if String(data: data, encoding: .utf8) != nil { encoding = .utf8 }
    else {
      encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    }
    guard let decoded = String(data: data, encoding: encoding) else { throw ClientError.message("无法读取文本编码") }
    let body = decoded.hasPrefix("\u{FEFF}") ? String(decoded.dropFirst()) : decoded
    guard !body.contains("\0"), !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, body.utf16.count <= 300_000 else {
      throw ClientError.message("正文为空、非文本或超过30万字")
    }
    return ImportedKnowledge(title: (filename as NSString).deletingPathExtension, body: body)
  }
  public static func read(_ url: URL) throws -> ImportedKnowledge {
    let allowed = url.startAccessingSecurityScopedResource()
    defer { if allowed { url.stopAccessingSecurityScopedResource() } }
    guard let stream = InputStream(url: url) else { throw ClientError.message("无法读取文件") }
    stream.open(); defer { stream.close() }
    var result = Data(); var buffer = [UInt8](repeating: 0, count: 8192)
    while result.count <= 1_048_576 {
      let count = stream.read(&buffer, maxLength: min(buffer.count, 1_048_577-result.count))
      if count < 0 { throw stream.streamError ?? ClientError.message("无法读取文件") }
      if count == 0 { break }
      result.append(contentsOf: buffer.prefix(count))
    }
    return try decode(result, filename: url.lastPathComponent)
  }
}
