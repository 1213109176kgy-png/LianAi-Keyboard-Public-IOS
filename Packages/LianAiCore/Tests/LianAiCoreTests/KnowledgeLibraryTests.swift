import XCTest
import CoreFoundation
@testable import LianAiCore

@MainActor
final class KnowledgeLibraryTests: XCTestCase {
  private func make() throws -> (KnowledgeLibrary, URL, UserDefaults) {
    let id = UUID().uuidString
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("knowledge-tests-" + id)
    let defaults = UserDefaults(suiteName: "knowledge-tests-" + id)!
    return (KnowledgeLibrary(directory: directory, defaults: defaults), directory, defaults)
  }
  func testBothBuiltinsAreReadOnlyAndDefaultSelectionIsShared() async throws {
    let (library, directory, defaults) = try make(); defer { try? FileManager.default.removeItem(at: directory) }
    let initial = try library.read()
    XCTAssertEqual(initial.documents.count, 2)
    XCTAssertEqual(initial.selectedDocument?.id, AIKnowledge.goutoujunshi.documentID)
    for document in initial.documents {
      XCTAssertTrue(document.isSystem)
      XCTAssertThrowsError(try library.save(document))
      XCTAssertThrowsError(try library.remove(document.id))
    }
    let second = KnowledgeLibrary(directory: directory, defaults: defaults)
    let tong = AIKnowledge.tongJincheng.documentID!
    try library.setEnabled(tong, false)
    try library.setDefault(tong)
    XCTAssertEqual(try second.read().selectedDocument?.id, tong)
    XCTAssertEqual(try second.read().defaultDocumentID, tong)
    XCTAssertTrue(try second.read().documents.first { $0.id == tong }!.enabled)
  }
  func testCustomCreateEditSearchDisableAndDeleteArePersistent() async throws {
    let (library, directory, defaults) = try make(); defer { try? FileManager.default.removeItem(at: directory) }
    var document = KnowledgeDocument(title: "自建资料", body: "# 邀约\n周末见面要给对方准备时间。")
    try library.save(document)
    try library.setDefault(document.id)
    let snapshot = try library.snapshot()
    XCTAssertTrue(snapshot.reference(for: "周末见面").contains("准备时间"))
    document.title = "更新后的资料"; document.body += "\n仅此资料的唯一标记"
    try library.save(document)
    XCTAssertFalse(library.isCurrent(snapshot), "资料更新必须使旧 AI 结果失效")
    let second = KnowledgeLibrary(directory: directory, defaults: defaults)
    XCTAssertEqual(try second.read().matching("唯一标记").map(\.id), [document.id])
    try second.setEnabled(document.id, false)
    XCTAssertNil(try library.read().selectedDocument)
    try second.setDefault(document.id)
    XCTAssertEqual(try library.read().selectedDocument?.id, document.id)
    try library.remove(document.id)
    XCTAssertNil(try second.read().defaultDocumentID)
    XCTAssertNil(try second.read().selectedDocumentID)
    XCTAssertTrue(try second.read().matching("唯一标记").isEmpty)
  }
  func testLegacySelectionMigratesAndExplicitNoneStaysNone() async throws {
    let (library, directory, defaults) = try make(); defer { try? FileManager.default.removeItem(at: directory) }
    defaults.set("tongJincheng", forKey: "ai.knowledge")
    XCTAssertEqual(try library.read().selectedDocument?.id, AIKnowledge.tongJincheng.documentID)
    try library.select(nil)
    XCTAssertNil(try KnowledgeLibrary(directory: directory, defaults: defaults).read().selectedDocumentID)
    XCTAssertEqual(try library.snapshot().reference(for: "邀约"), "")
  }
  func testCorruptFileCannotBeOverwrittenBySave() async throws {
    let (library, directory, _) = try make(); defer { try? FileManager.default.removeItem(at: directory) }
    _ = try library.read()
    let original = Data("broken document library".utf8)
    try original.write(to: library.fileURL)
    XCTAssertThrowsError(try library.save(KnowledgeDocument(title: "新资料", body: "内容")))
    XCTAssertEqual(try Data(contentsOf: library.fileURL), original)
  }
  func testValidationUsesAndroidUTF16LimitsAndRejectsDisabledSelection() async throws {
    let (library, directory, _) = try make(); defer { try? FileManager.default.removeItem(at: directory) }
    XCTAssertThrowsError(try library.save(KnowledgeDocument(title: " ", body: "正文")))
    XCTAssertThrowsError(try library.save(KnowledgeDocument(title: String(repeating: "😀", count: 61), body: "正文")))
    XCTAssertThrowsError(try library.save(KnowledgeDocument(title: "标题", body: String(repeating: "字", count: 300_001))))
    let document = KnowledgeDocument(title: "停用资料", body: "正文", enabled: false)
    try library.save(document)
    XCTAssertThrowsError(try library.select(document.id))
  }
}

final class KnowledgeImportAndMarkdownTests: XCTestCase {
  func testUTF8UTF16AndGB18030ImportsRetainText() throws {
    let source = "# 导入资料\n**测试**邀约内容"
    let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    let data = [Data(source.utf8), Data([0xff,0xfe]) + source.data(using: .utf16LittleEndian)!, Data([0xfe,0xff]) + source.data(using: .utf16BigEndian)!, source.data(using: gb)!]
    for bytes in data {
      let result = try KnowledgeImport.decode(bytes, filename: "资料.MD")
      XCTAssertEqual(result.title, "资料"); XCTAssertEqual(result.body, source)
    }
  }
  func testImportRejectsWrongTypeBinaryEmptyOversizeAndTooMuchText() {
    for (bytes, filename) in [(Data("text".utf8), "a.pdf"), (Data("\0binary".utf8), "a.txt"), (Data(" \n".utf8), "a.md"), (Data(repeating: 97, count: 1_048_577), "a.txt"), (Data(String(repeating: "字", count: 300_001).utf8), "a.md")] {
      XCTAssertThrowsError(try KnowledgeImport.decode(bytes, filename: filename))
    }
  }
  func testTablesUseFullWidthLabelledRowsAndCodeIsNotReinterpreted() {
    let blocks = KnowledgeMarkdown.parse("# 标题\n| 场景 | 方法 |\n| --- | --- |\n| 邀约 | 低压力，给准备时间 |\n```\n# 原样代码\n```\n![说明](https://example.com/image.png)")
    XCTAssertEqual(blocks.first?.kind, .heading(1))
    XCTAssertTrue(blocks.contains { $0.text == "**场景**：邀约\n**方法**：低压力，给准备时间" })
    XCTAssertTrue(blocks.contains { $0.kind == .code && $0.text == "# 原样代码" })
    XCTAssertEqual(blocks.last?.text, "说明")
  }
}
