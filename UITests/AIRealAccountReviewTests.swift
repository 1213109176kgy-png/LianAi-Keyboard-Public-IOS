import XCTest
import UIKit

/// Optional live acceptance. Credentials are supplied only to the test runner
/// environment, never committed in source or fixtures.
@MainActor
final class AIRealAccountReviewTests: XCTestCase {
  nonisolated override func setUpWithError() throws { continueAfterFailure = false }
  func testLiveReplyAndSuperSpeakResults() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let phone = environment["LIANAI_REVIEW_PHONE"],
      let password = environment["LIANAI_REVIEW_PASSWORD"] else {
      throw XCTSkip("Live review requires an explicitly supplied test account")
    }
    let app = XCUIApplication()
    app.launchEnvironment["LIANAI_PREVIEW_PAGE"] = "profile"
    app.launchEnvironment["LIANAI_REVIEW_SOURCE"] = "Tomorrow can we have dinner?"
    app.launch()
    let login = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "未登录")).firstMatch
    if login.waitForExistence(timeout: 8) {
      login.tap()
      let phoneField = app.textFields["手机号"]
      XCTAssertTrue(phoneField.waitForExistence(timeout: 4), app.debugDescription)
      phoneField.tap(); phoneField.typeText(phone)
      let secret = app.secureTextFields["密码（8~64 位）"]
      secret.tap(); secret.typeText(password)
      app.buttons["登录"].tap()
      XCTAssertTrue(app.buttons["changePasswordEntry"].waitForExistence(timeout: 30), app.debugDescription)
    }
    app.buttons["键盘"].tap()
    app.textViews["trialInput"].tap()
    let mode = app.buttons["keyboardMode.帮你回"]
    XCTAssertTrue(mode.waitForExistence(timeout: 10), app.debugDescription)
    if !mode.isHittable { app.buttons["试用键盘"].tap(); app.textViews["trialInput"].tap() }
    mode.tap()
    app.buttons["replyPaste"].tap()
    confirmPaste(app)
    if app.buttons["keyboardPromptPrimary"].waitForExistence(timeout: 2) { app.buttons["keyboardPromptPrimary"].tap() }
    XCTAssertTrue(app.buttons["aiResult.0"].waitForExistence(timeout: 90), app.debugDescription)
    capture("live-reply", app)
    let first = app.buttons["aiResult.0"].label
    app.buttons["aiResult.0"].tap()
    XCTAssertEqual(app.textViews["trialInput"].value as? String, first)
    let second = app.buttons["aiResult.1"].label
    app.buttons["aiResult.1"].tap()
    XCTAssertEqual(app.textViews["trialInput"].value as? String, second)
    app.buttons["keyboardMode.超会说"].tap()
    // Use the same source as Android through the real keyboard paste action.
    app.buttons["粘贴"].tap()
    confirmPaste(app)
    XCTAssertTrue(app.staticTexts["keyboardAIDraft"].label.contains("Tomorrow can we have dinner?"))
    XCTAssertEqual(app.textViews["trialInput"].value as? String, second)
    app.buttons["aiDraftGenerate"].tap()
    XCTAssertTrue(app.buttons["aiResult.0"].waitForExistence(timeout: 90), app.debugDescription)
    capture("live-polish", app)
    let polished = app.buttons["aiResult.0"].label
    app.buttons["aiResult.0"].tap()
    XCTAssertEqual(app.textViews["trialInput"].value as? String, second + polished)
    app.buttons["aiNewContent"].tap()
    XCTAssertTrue(app.buttons["aiDraftGenerate"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.textViews["trialInput"].value as? String, second + polished)
  }
  private func capture(_ name: String, _ app: XCUIApplication) {
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = name; image.lifetime = .keepAlways; add(image)
  }
  private func confirmPaste(_ app: XCUIApplication) {
    let predicate = NSPredicate(format: "label IN %@", ["允许粘贴", "Allow Paste"])
    // The system owns this sheet. Querying the host first can deadlock while
    // UIPasteboard is synchronously waiting for the permission response.
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    for _ in 0..<3 {
      let allow = springboard.buttons.matching(predicate).firstMatch
      if allow.waitForExistence(timeout: 2) { allow.tap() } else { break }
    }
  }
}
