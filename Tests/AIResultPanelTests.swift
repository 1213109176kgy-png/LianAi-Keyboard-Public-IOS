import XCTest
import UIKit
@testable import LianAiKeyboard

@MainActor
final class AIResultPanelTests: XCTestCase {
  func testLongChoicesRemainReadableAndAllThreeAreIndependentTargets() {
    let values = (1...3).map { "第\($0)条：" + String(repeating: "谢谢你认真告诉我你的想法。", count: 12) }
    var chosen: String?
    let panel = AIResultPanel(polish: false, compact: false, dark: false, loading: false,
      emotion: "积极期待", options: values, close: {}, choose: { chosen = $0 }, retry: {}, newContent: {})
    panel.frame = CGRect(x: 0, y: 0, width: 390, height: 421)
    panel.layoutIfNeeded()
    XCTAssertEqual(panel.optionButtons.count, 3)
    for (index, button) in panel.optionButtons.enumerated() {
      XCTAssertFalse(button.textLabel.adjustsFontSizeToFitWidth, "长文应截尾，不能缩成小字")
      XCTAssertEqual(button.accessibilityLabel, values[index], "上屏与无障碍必须保留完整原文")
      XCTAssertTrue(panel.card.bounds.contains(button.frame))
      if index > 0 { XCTAssertFalse(button.frame.intersects(panel.optionButtons[index-1].frame)) }
      button.sendActions(for: .touchUpInside)
      XCTAssertEqual(chosen, values[index])
    }
    XCTAssertNotNil(panel.retryButton)
    XCTAssertNil(panel.newContentButton)
  }
  func testCompactPolishKeepsNewContentAndCloseSeparateFromChoices() {
    let panel = AIResultPanel(polish: true, compact: true, dark: true, loading: false,
      emotion: "", options: ["第一条", "第二条", "第三条"], close: {}, choose: { _ in }, retry: {}, newContent: {})
    panel.frame = CGRect(x: 0, y: 0, width: 600, height: 246)
    panel.layoutIfNeeded()
    let fresh = panel.newContentButton!
    XCTAssertFalse(fresh.frame.intersects(panel.closeButton.frame))
    for button in panel.optionButtons {
      XCTAssertTrue(panel.card.bounds.contains(button.frame))
      XCTAssertFalse(button.frame.intersects(fresh.frame))
      XCTAssertFalse(button.frame.intersects(panel.closeButton.frame))
    }
    XCTAssertNil(panel.retryButton)
  }
}
