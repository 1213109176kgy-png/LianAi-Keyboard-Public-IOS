import XCTest

@MainActor
final class KeyboardSetupFlowTests: XCTestCase {
  nonisolated override func setUpWithError() throws { continueAfterFailure = false }
  private func capture(_ name: String, _ app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
  }
  private func accessSwitch(_ settings: XCUIApplication) -> XCUIElement {
    func find(_ labels: [String]) -> XCUIElement {
      settings.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }
    if settings.searchFields.firstMatch.exists {
      let cancel = settings.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
      if cancel.exists { cancel.tap() }
    }
    for _ in 0..<10 {
      if settings.navigationBars["设置"].exists || settings.navigationBars["Settings"].exists { break }
      if settings.navigationBars.buttons.firstMatch.exists { settings.navigationBars.buttons.firstMatch.tap() }
    }
    if !find(["通用", "General"]).isHittable { settings.swipeUp() }
    find(["通用", "General"]).tap()
    if !find(["键盘", "Keyboard"]).isHittable { settings.swipeUp() }
    find(["键盘", "Keyboard"]).tap()
    let keyboards = settings.descendants(matching: .any).matching(identifier: "KEYBOARDS").firstMatch
    XCTAssertTrue(keyboards.waitForExistence(timeout: 5), settings.debugDescription)
    keyboards.tap()
    if !find(["恋爱键盘"]).exists {
      settings.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "添加新键盘", "Add New Keyboard")).firstMatch.tap()
      find(["恋爱键盘"]).tap()
    }
    find(["恋爱键盘"]).tap()
    let toggle = settings.switches.matching(NSPredicate(format: "label IN %@", ["允许完全访问", "Allow Full Access"])).firstMatch
    XCTAssertTrue(toggle.waitForExistence(timeout: 5), settings.debugDescription)
    return toggle
  }
  private func chooseKeyboard(_ app: XCUIApplication) {
    let keyboard = app.buttons["keyboardMode.键盘"]
    if keyboard.waitForExistence(timeout: 3) && keyboard.isHittable { return }
    let continueButton = app.buttons.matching(NSPredicate(format: "label IN %@", ["Continue", "继续"])).firstMatch
    if continueButton.exists { continueButton.tap() }
    let next = app.buttons.matching(NSPredicate(format: "label IN %@", ["Next keyboard", "下一个键盘", "下一键盘"])).firstMatch
    XCTAssertTrue(next.waitForExistence(timeout: 5), app.debugDescription)
    next.press(forDuration: 1)
    let choice = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "恋爱键盘")).firstMatch
    XCTAssertTrue(choice.waitForExistence(timeout: 3), app.debugDescription)
    choice.tap()
  }
  /// Run on an isolated, freshly installed simulator. No test flags or fake permissions.
  func testFirstLaunchSettingsRoundTripRealPermissionAndNoRepeat() {
    let app = XCUIApplication()
    app.launch()
    XCTAssertTrue(app.buttons["keyboardSetupSettings"].waitForExistence(timeout: 12))
    capture("首次启动-自动设置引导", app)
    app.buttons["keyboardSetupLater"].tap()
    app.terminate(); app.launch()
    XCTAssertTrue(app.buttons["keyboardSetupSettings"].waitForExistence(timeout: 12))
    app.buttons["keyboardSetupSettings"].tap()
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 8))
    app.activate()
    XCTAssertTrue(app.staticTexts["keyboardSetupStatus"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["keyboardSetupStatus"].label, "已返回，请切换到恋爱键盘完成验证")
    XCTAssertFalse(app.staticTexts["keyboardSetupComplete"].exists)
    capture("返回未启用-保持未完成", app)
    app.buttons["keyboardSetupClose"].tap()
    app.terminate(); app.launch()
    XCTAssertTrue(app.buttons["keyboardSetupSettings"].waitForExistence(timeout: 12))
    app.buttons["keyboardSetupSettings"].tap()
    XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 8))
    let access = accessSwitch(settings)
    XCTAssertEqual(access.value as? String, "0", "全新模拟器应尚未授予完全访问")
    app.activate()
    app.textFields["keyboardSetupInput"].tap()
    chooseKeyboard(app)
    XCTAssertTrue(app.buttons["keyboardMode.键盘"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["keyboardSetupComplete"].exists)
    let input = app.textFields["keyboardSetupInput"]
    XCTAssertTrue(input.isHittable)
    XCTAssertLessThan(input.frame.maxY, app.buttons["keyboardMode.键盘"].frame.minY,
      "验证输入框应完整显示在键盘上方")
    capture("已启用但未完全访问-保持未完成", app)
    // The setup button stays reachable after dismissing the validation keyboard.
    app.buttons["⌄"].tap()
    if !app.buttons["keyboardSetupSettings"].isHittable { app.swipeDown() }
    app.buttons["keyboardSetupSettings"].tap()
    XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 8))
    let enabled = accessSwitch(settings)
    let inner = enabled.descendants(matching: .switch).firstMatch
    if inner.exists { inner.tap() } else { enabled.tap() }
    let allow = settings.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["允许", "Allow"])).firstMatch
    if allow.waitForExistence(timeout: 3) { allow.tap() }
    XCTAssertEqual(enabled.value as? String, "1")
    // Relaunch also verifies recovery if the containing app was terminated while
    // Settings changed the keyboard's access. Do not depend on a suspended process.
    app.launch()
    // The real keyboard records its Full Access receipt when it appears on return.
    if !app.staticTexts["keyboardSetupComplete"].waitForExistence(timeout: 8) {
      app.textFields["keyboardSetupInput"].tap()
      chooseKeyboard(app)
    }
    XCTAssertTrue(app.staticTexts["keyboardSetupComplete"].waitForExistence(timeout: 10), app.debugDescription)
    capture("设置完成-真实键盘权限验证", app)
    app.buttons["keyboardSetupFinish"].tap()
    app.terminate(); app.launch()
    XCTAssertTrue(app.buttons["我的"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["keyboardSetupSettings"].waitForExistence(timeout: 3))
    capture("再次打开-不重复提示", app)
  }
}
