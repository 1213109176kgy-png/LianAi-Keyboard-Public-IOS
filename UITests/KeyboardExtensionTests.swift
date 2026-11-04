import XCTest
import UIKit

@MainActor
final class KeyboardExtensionTests: XCTestCase {
  func testSystemKeyboardCanBeEnabledAndInsertChinese() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["LIANAI_PREVIEW_PAGE"] = "test"
    app.launch()
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    settings.launch()
    if settings.searchFields.firstMatch.exists {
      let cancelSearch = settings.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
      if cancelSearch.exists { cancelSearch.tap() }
    }
    func find(_ titles: [String]) -> XCUIElement {
      settings.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", titles))
        .firstMatch
    }
    for _ in 0..<6 {
      if settings.navigationBars["设置"].exists || settings.navigationBars["Settings"].exists {
        break
      }
      if settings.navigationBars.buttons.firstMatch.exists {
        settings.navigationBars.buttons.firstMatch.tap()
      }
    }
    if !find(["通用", "General"]).exists { settings.swipeUp() }
    find(["通用", "General"]).tap()
    let keyboard = find(["键盘", "Keyboard"])
    if !keyboard.exists { settings.swipeUp() }
    keyboard.tap()
    let keyboardsPage = settings.descendants(matching: .any).matching(identifier: "KEYBOARDS").firstMatch
    if !keyboardsPage.waitForExistence(timeout: 2) {
      // Restored Settings scroll positions can move a row during the first tap.
      // Confirm the destination and retry the actual Keyboard row, not its label.
      let back = settings.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["通用", "General"])).firstMatch
      if back.exists { back.tap() }
      let row = settings.descendants(matching: .any).matching(identifier: "com.apple.settings.general.keyboard").firstMatch
      XCTAssertTrue(row.waitForExistence(timeout: 3), settings.debugDescription)
      row.tap()
    }
    XCTAssertTrue(keyboardsPage.waitForExistence(timeout: 3), settings.debugDescription)
    keyboardsPage.tap()
    if !find(["恋爱键盘"]).exists {
      settings.descendants(matching: .any).matching(
        NSPredicate(
          format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "添加新键盘", "Add New Keyboard")
      ).firstMatch.tap()
      find(["恋爱键盘"]).tap()
    }
    app.activate()
    let input = app.textViews["trialInput"]
    app.buttons["试用键盘"].tap()
    let visible = NSPredicate(format: "exists == true AND hittable == true")
    if XCTWaiter.wait(
      for: [XCTNSPredicateExpectation(predicate: visible, object: app.buttons["帮你回"])], timeout: 3)
      != .completed
    {
      let next = app.buttons.matching(
        NSPredicate(format: "label IN %@", ["Next keyboard", "下一个键盘", "下一键盘"])
      ).firstMatch
      if next.exists { next.press(forDuration: 1) }
      let choice = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "恋爱键盘"))
        .firstMatch
      if choice.exists { choice.tap() }
    }
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [XCTNSPredicateExpectation(predicate: visible, object: app.buttons["MNO"])],
        timeout: 10), .completed, app.debugDescription)
    app.buttons["MNO"].tap()
    app.buttons["GHI"].tap()
    XCTAssertTrue(app.buttons["你"].waitForExistence(timeout: 5))
    assertCandidateTextIsReadable(app.buttons["你"])
    capture("系统键盘-九键拼音与候选", app)
    app.buttons["你"].tap()
    XCTAssertTrue(input.waitForExistence(timeout: 3))
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "你"), object: input)], timeout: 5), .completed, app.debugDescription)
    capture("系统键盘-九键中文上屏", app)
    app.buttons.matching(identifier: "ABC").element(boundBy: 1).tap()
    for letter in ["h", "e", "l", "l"] { app.buttons[letter].tap() }
    XCTAssertTrue(app.buttons["hello"].waitForExistence(timeout: 3))
    assertCandidateTextIsReadable(app.buttons["hello"])
    app.buttons["hello"].tap()
    XCTAssertTrue((input.value as? String ?? "").hasSuffix("hello"))
    capture("系统键盘-英文补全", app)
    for letter in ["h", "i"] { app.buttons[letter].tap() }
    app.buttons["空格"].tap()
    XCTAssertTrue((input.value as? String ?? "").hasSuffix("hi "), "英文组合按空格必须补一个空格")
    if !app.buttons["帮你回"].isHittable && app.buttons["×"].exists { app.buttons["×"].tap() }
    app.buttons["帮你回"].tap()
    XCTAssertTrue(app.buttons["+  粘贴TA的话"].exists)
    capture("系统键盘-帮你回", app)
    app.buttons["超会说"].tap()
    for letter in ["h", "i"] { app.buttons[letter].tap() }
    XCTAssertFalse((input.value as? String ?? "").hasSuffix("hi"), "草稿不能写入宿主")
    let hostBeforeEnter = input.value as? String
    XCTAssertTrue(app.buttons["keyboardMode.键盘"].isHittable, "草稿英文候选不能遮住模式切换")
    app.buttons["keyboardEnter"].tap()
    XCTAssertEqual(input.value as? String, hostBeforeEnter, "超会说换行只写入内部草稿")
    capture("系统键盘-超会说草稿", app)
    app.buttons["keyboardMode.键盘"].tap()
    XCTAssertTrue(app.buttons["帮你回"].isHittable)
    app.buttons["123"].tap()
    app.buttons["›"].tap()
    app.buttons["›"].tap()
    XCTAssertTrue(app.buttons["3/3"].exists)
    app.buttons["——"].tap()
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value ENDSWITH %@", "——"), object: input)], timeout: 3), .completed)
    capture("系统键盘-中文符号第三页", app)
    app.buttons["返回拼音"].tap()
    app.buttons["^_^"].tap()
    XCTAssertTrue(app.buttons["QAQ"].waitForExistence(timeout: 3))
    app.buttons["QAQ"].tap()
    app.buttons["123"].tap()
    XCTAssertEqual(app.buttons.matching(identifier: "keyboardEnter").count, 1, "数字面板只能有一个跨行发送键")
    capture("系统键盘-数字面板", app)
    app.buttons["拼音"].tap()
    app.buttons["☺"].tap()
    app.buttons["›"].tap()
    XCTAssertTrue(app.buttons["2/2"].exists, "常用表情必须包含完整40项")
    XCTAssertTrue(app.buttons["😁"].exists)
    capture("系统键盘-常用表情第二页", app)
    app.buttons["返回键盘"].tap()
    XCUIDevice.shared.orientation = .landscapeLeft
    defer { XCUIDevice.shared.orientation = .portrait }
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: app.buttons["MNO"])], timeout: 5), .completed)
    capture("系统键盘-横屏九键", app)
  }
  private func assertCandidateTextIsReadable(_ candidate: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
    // Existence and hit testing also pass when UIKit's scroll edge effect blurs
    // a short candidate strip. Check the rendered foreground contrast as well.
    guard let image = candidate.screenshot().image.cgImage else {
      XCTFail("无法读取候选字截图", file: file, line: line)
      return
    }
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let readable = pixels.withUnsafeMutableBytes { bytes -> Int in
      guard let context = CGContext(
        data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
      ) else { return 0 }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      let rgba = bytes.bindMemory(to: UInt8.self)
      return stride(from: 0, to: rgba.count, by: 4).reduce(0) { count, index in
        count + (rgba[index + 3] > 240 && max(rgba[index], rgba[index + 1], rgba[index + 2]) < 110 ? 1 : 0)
      }
    }
    XCTAssertGreaterThan(Double(readable) / Double(max(1, width * height)), 0.003,
      "候选字必须有清晰的深色笔画，不能只存在于无障碍树中", file: file, line: line)
  }
  private func capture(_ name: String, _ app: XCUIApplication) {
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = name
    image.lifetime = .keepAlways
    add(image)
  }
}
