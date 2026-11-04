import XCTest

@MainActor
final class KeyboardTypingUITests: XCTestCase {
  nonisolated override func setUpWithError() throws { continueAfterFailure = false }
  func testRepeatedTypingHasNoFooterGapAndKeepsGridAnchored() {
    let app = XCUIApplication()
    app.launchEnvironment["LIANAI_PREVIEW_PAGE"] = "test"
    app.launch()
    XCTAssertTrue(app.buttons["试用键盘"].waitForExistence(timeout: 10))
    app.buttons["试用键盘"].tap()
    if !app.buttons["MNO"].waitForExistence(timeout: 3) {
      let globe = app.buttons.matching(NSPredicate(format: "label IN %@", ["Next keyboard", "下一个键盘", "下一键盘"])).firstMatch
      if globe.exists { globe.press(forDuration: 1) }
      let choice = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "恋爱键盘")).firstMatch
      if choice.exists { choice.tap() }
    }
    XCTAssertTrue(app.buttons["MNO"].waitForExistence(timeout: 8), app.debugDescription)
    let content = app.otherElements["keyboardContent"]
    let keys = app.otherElements["keyboardTypingKeys"]
    XCTAssertTrue(content.exists && keys.exists, app.debugDescription)
    XCTAssertLessThanOrEqual(abs(content.frame.maxY - keys.frame.maxY), 1, "按键下方不应再有光标滑块或占位条")
    let space = app.buttons["keyboardSpace"].frame
    let rounds = 8
    for count in 1...rounds {
      for name in ["t9Key.6", "t9Key.4", "t9Key.4", "t9Key.2", "t9Key.6"] { app.buttons[name].tap() }
      let nihao = app.buttons["你好"]
      XCTAssertTrue(nihao.waitForExistence(timeout: 3), app.debugDescription)
      if count == 1 {
        let beforeSwipe = app.textViews["trialInput"].value as? String
        let candidates = app.scrollViews["keyboardCandidateScroll"]
        candidates.swipeLeft(); candidates.swipeRight()
        XCTAssertEqual(app.textViews["trialInput"].value as? String, beforeSwipe, "滑动候选不得提前提交")
        // Start a fresh composition before the commit check. Candidate scroll
        // deceleration differs on simulator/device; cancellation is verified
        // above without depending on the exact final horizontal offset.
        for _ in 0..<5 { app.buttons["⌫"].tap() }
        for name in ["t9Key.6", "t9Key.4", "t9Key.4", "t9Key.2", "t9Key.6"] { app.buttons[name].tap() }
        XCTAssertTrue(nihao.waitForExistence(timeout: 3))
      }
      nihao.tap()
      let expected = String(repeating: "你好", count: count)
      let inserted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: app.textViews["trialInput"])
      let result = XCTWaiter.wait(for: [inserted], timeout: 5)
      if result != .completed {
        let failure = XCTAttachment(screenshot: app.screenshot()); failure.name = "连续输入-上屏失败"; failure.lifetime = .keepAlways; add(failure)
      }
      XCTAssertEqual(result, .completed, app.debugDescription)
      XCTAssertLessThanOrEqual(abs(content.frame.maxY - keys.frame.maxY), 1)
      XCTAssertEqual(app.buttons["keyboardSpace"].frame.maxY, space.maxY, accuracy: 1)
    }
    if app.buttons["×"].exists { app.buttons["×"].tap() }
    // The far-left ABC changes language; the other ABC is T9 digit 2.
    let language = app.buttons.matching(identifier: "ABC").allElementsBoundByIndex.min { $0.frame.minX < $1.frame.minX }
    XCTAssertNotNil(language)
    language?.tap()
    for letter in ["h", "e", "l", "l", "o"] {
      app.buttons.matching(NSPredicate(format: "label ==[c] %@", letter)).firstMatch.tap()
    }
    let delete = app.buttons.matching(NSPredicate(format: "label == %@", "⌫")).firstMatch
    delete.tap()
    app.buttons.matching(NSPredicate(format: "label ==[c] %@", "o")).firstMatch.tap()
    app.buttons["keyboardSpace"].tap()
    let english = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", String(repeating: "你好", count: rounds) + "hello "),
      object: app.textViews["trialInput"])
    XCTAssertEqual(XCTWaiter.wait(for: [english], timeout: 5), .completed, app.debugDescription)
    app.buttons["中/EN"].tap()
    XCTAssertTrue(app.buttons["t9Key.6"].exists)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "连续输入-移除底部占位条"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }
}
