import XCTest
import UIKit
@testable import LianAiKeyboard

@MainActor
final class KeyboardTouchTests: XCTestCase {
  func testLetterCommitsOnContactOnceAndWorksForAccessibility() {
    var output = ""
    let key = InputKey("a", background: .white, foreground: .black) { output += "a" }
    key.activatesOnTouchDown = true
    key.sendActions(for: .touchDown)
    XCTAssertEqual(output, "a", "触摸落下即输入，不等待手指抬起")
    key.sendActions(for: .touchUpInside)
    XCTAssertEqual(output, "a", "松开不得重复输入")
    key.sendActions(for: .touchDown)
    key.sendActions(for: .touchCancel)
    XCTAssertEqual(output, "aa")
    XCTAssertTrue(key.accessibilityActivate())
    XCTAssertEqual(output, "aaa")
    XCTAssertTrue(key.gestureRecognizers?.contains { ($0 as? UILongPressGestureRecognizer)?.minimumPressDuration == 0.42 } != true)
  }
  func testSpaceAndScrollableChoicesWaitForReleaseAndCancelSafely() {
    var count = 0
    let key = InputKey("空格", background: .white, foreground: .black) { count += 1 }
    key.holdAction = {}
    XCTAssertEqual(key.gestureRecognizers?.filter { ($0 as? UILongPressGestureRecognizer)?.minimumPressDuration == 0.42 }.count, 1)
    key.sendActions(for: .touchDown)
    XCTAssertEqual(count, 0, "保留长按语音，不在按下时提前插入空格")
    key.sendActions(for: .touchCancel)
    XCTAssertEqual(count, 0)
    key.sendActions(for: .touchDown)
    key.sendActions(for: .touchUpInside)
    XCTAssertEqual(count, 1)
    key.holdAction = nil
    XCTAssertTrue(key.gestureRecognizers?.contains { ($0 as? UILongPressGestureRecognizer)?.minimumPressDuration == 0.42 } != true)
  }
  func testChangingCandidatesReusesButtonsWithFreshActionsAndCanShrink() {
    let strip = KeyboardChoiceStrip(spacing: 8)
    var output = ""
    var created = 0
    func update(_ titles: [String]) {
      strip.update(titles, make: { title in
        created += 1
        return InputKey(title, background: .white, foreground: .black) {}
      }) { key, index in
        key.pressed = { output += titles[index] }
        return 44
      }
    }
    update(["你", "好", "吗"])
    let line = strip.scroll.subviews.compactMap { $0 as? UIStackView }.first!
    let first = line.arrangedSubviews[0] as! InputKey
    update(["你好", "您好"])
    XCTAssertEqual(created, 3)
    XCTAssertTrue(first === line.arrangedSubviews[0])
    first.sendActions(for: .touchDown)
    XCTAssertEqual(output, "", "滚动候选不得在落指时上屏")
    first.sendActions(for: .touchUpInside)
    XCTAssertEqual(output, "你好", "复用按钮必须选择新候选，不得保留旧闭包")
    XCTAssertTrue(line.arrangedSubviews[2].isHidden)
    update(["甲", "乙", "丙", "丁"])
    XCTAssertEqual(created, 4)
    XCTAssertFalse(line.arrangedSubviews[2].isHidden)
    XCTAssertFalse(strip.scroll.delaysContentTouches)
    XCTAssertTrue(strip.scroll.touchesShouldCancel(in: first), "立即触摸后，滑动仍必须能取消候选按钮")
  }
}
