import XCTest
@testable import LianAiCore

final class AIKnowledgeTests: XCTestCase {
  func testBuiltInDocumentsAreBundledAndReferencesAreBounded() {
    for knowledge in AIKnowledge.allCases where knowledge != .none {
      let reference = knowledge.reference(for: "明天一起吃饭吧，周末有空见面吗？")
      XCTAssertTrue(reference.contains(knowledge.title))
      XCTAssertTrue(reference.contains("只根据用户原话完成原任务"))
      XCTAssertLessThan(reference.count, 5100)
    }
    XCTAssertEqual(AIKnowledge.none.reference(for: "明天一起吃饭"), "")
  }
}
