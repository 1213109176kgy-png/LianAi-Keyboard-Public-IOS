import XCTest

@MainActor
final class NativeVoiceSessionTests: XCTestCase {
  nonisolated override func setUpWithError() throws { continueAfterFailure = false }
  private func allowPermissionIfPresent(_ app: XCUIApplication) {
    for source in [app, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
      let alert = source.alerts.firstMatch
      if alert.waitForExistence(timeout: 1) {
        let allow = alert.buttons.matching(NSPredicate(format: "label IN %@", ["允许", "Allow", "好", "OK", "使用 App 时允许", "Allow While Using App"])).firstMatch
        if allow.exists { allow.tap() }
      }
    }
  }
  /// Exercises real TCC prompts and AVAudioEngine, with no fixture capture.
  /// Actual microphone speech quality still requires a human/device utterance.
  func testNativeMicrophoneSessionArmsAndStopsWithoutFixture() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["LIANAI_PREVIEW_PAGE"] = "permissions"
    app.launch()
    XCTAssertTrue(app.buttons["录音权限"].waitForExistence(timeout: 10))
    app.buttons["录音权限"].tap()
    allowPermissionIfPresent(app)
    XCTAssertTrue(app.buttons["开启键盘语音"].waitForExistence(timeout: 5), app.debugDescription)
    app.buttons["开启键盘语音"].tap()
    allowPermissionIfPresent(app)
    let ready = app.buttons["关闭语音会话"]
    let status = app.staticTexts["voiceSessionStatus"]
    guard ready.waitForExistence(timeout: 15) else {
      let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "原生语音会话-模拟器限制"; attachment.lifetime = .keepAlways; add(attachment)
      // An unavailable simulator Speech service is a reported limitation, never
      // silently represented as a successful microphone/ASR test.
      if status.label.contains("暂不可用") || status.label.contains("设备") {
        throw XCTSkip("模拟器原生语音服务不可用：" + status.label)
      }
      XCTFail("真实语音会话未就绪：" + status.label + "\n" + app.debugDescription); return
    }
    let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "原生麦克风与语音权限-会话就绪"; attachment.lifetime = .keepAlways; add(attachment)
    ready.tap()
    XCTAssertTrue(app.buttons["开启键盘语音"].waitForExistence(timeout: 5))
    XCTAssertEqual(status.label, "语音会话已关闭")
  }
  func testNativeMicrophoneBackgroundRoundTripWithFixtureASR() throws {
    let app = XCUIApplication()
    app.launchEnvironment["LIANAI_PREVIEW_PAGE"] = "permissions"
    app.launchEnvironment["LIANAI_NATIVE_VOICE_TEST"] = "cloud"
    app.launch()
    XCTAssertTrue(app.buttons["录音权限"].waitForExistence(timeout: 10))
    app.buttons["录音权限"].tap()
    allowPermissionIfPresent(app)
    XCTAssertTrue(app.buttons["开启键盘语音"].waitForExistence(timeout: 5))
    app.buttons["开启键盘语音"].tap()
    XCTAssertTrue(app.buttons["关闭语音会话"].waitForExistence(timeout: 15), app.debugDescription)
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    defer { settings.terminate(); app.terminate() }
    settings.launch()
    for _ in 0..<8 {
      if settings.searchFields.firstMatch.exists { break }
      if settings.navigationBars.buttons.firstMatch.exists { settings.navigationBars.buttons.firstMatch.tap() }
    }
    let search = settings.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 5), settings.debugDescription)
    search.tap()
    if !settings.buttons["keyboardSpace"].waitForExistence(timeout: 3) {
      let globe = settings.buttons.matching(NSPredicate(format: "label IN %@", ["Next keyboard", "下一个键盘", "下一键盘"])).firstMatch
      if globe.exists { globe.press(forDuration: 1) }
      let keyboard = settings.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "恋爱键盘")).firstMatch
      if keyboard.exists { keyboard.tap() }
    }
    XCTAssertTrue(settings.buttons["keyboardSpace"].waitForExistence(timeout: 5), settings.debugDescription)
    settings.buttons["keyboardSpace"].press(forDuration: 1)
    let inserted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "原生音频测试。"), object: settings.searchFields.firstMatch)
    XCTAssertEqual(XCTWaiter.wait(for: [inserted], timeout: 10), .completed, settings.debugDescription)
    XCTAssertTrue(settings.buttons["keyboardSpace"].waitForExistence(timeout: 5), settings.debugDescription)
    let attachment = XCTAttachment(screenshot: settings.screenshot()); attachment.name = "原生语音-长按空格-跨App回填"; attachment.lifetime = .keepAlways; add(attachment)
    XCTAssertEqual(app.state, .runningBackground)
  }

}
