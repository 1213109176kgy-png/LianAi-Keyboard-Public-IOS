import XCTest
import UIKit

@MainActor
final class KeyboardAIFlowTests: XCTestCase {
  private static var fullAccessVerified = false
  private let visible = NSPredicate(format: "exists == true AND hittable == true")
  nonisolated override func setUpWithError() throws { continueAfterFailure = false }
  private func launch(_ scenario: String, voice: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["LIANAI_PREVIEW_PAGE"] = "test"
    app.launchEnvironment["LIANAI_AI_UI_TEST"] = scenario
    if let voice { app.launchEnvironment["LIANAI_VOICE_UI_TEST"] = voice }
    app.launch()
    XCTAssertTrue(app.buttons["试用键盘"].waitForExistence(timeout: 10))
    // Full Access is a persistent system permission. Verify/grant it once in
    // this runner; every later AI request still crosses the real extension's
    // hasFullAccess guard, without repeating the unrelated Settings navigation.
    if !Self.fullAccessVerified {
      let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
      settings.launch()
      if settings.searchFields.firstMatch.exists {
        let cancelSearch = settings.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
        if cancelSearch.exists { cancelSearch.tap() }
      }
      func find(_ titles: [String]) -> XCUIElement {
        settings.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", titles)).firstMatch
      }
      for _ in 0..<8 {
        if settings.navigationBars["设置"].exists || settings.navigationBars["Settings"].exists { break }
        if settings.navigationBars.buttons.firstMatch.exists { settings.navigationBars.buttons.firstMatch.tap() }
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
        settings.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "添加新键盘", "Add New Keyboard")).firstMatch.tap()
        find(["恋爱键盘"]).tap()
      }
      find(["恋爱键盘"]).tap()
      let access = settings.switches.matching(NSPredicate(format: "label IN %@", ["允许完全访问", "Allow Full Access"])).firstMatch
      XCTAssertTrue(access.waitForExistence(timeout: 3), settings.debugDescription)
      if access.value as? String == "0" {
        let toggle = access.descendants(matching: .switch).firstMatch
        if toggle.exists { toggle.tap() } else { access.tap() }
        let allow = settings.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["允许", "Allow"])).firstMatch
        if allow.waitForExistence(timeout: 2) { allow.tap() }
      }
      XCTAssertEqual(access.value as? String, "1", "必须实际授予完全访问，不能绕过系统权限分支")
      Self.fullAccessVerified = true
      // Settings can clear the simulator's shared pasteboard. Relaunch the
      // fixture host on return so this test's source is seeded at point of use.
      app.launch()
      XCTAssertTrue(app.buttons["试用键盘"].waitForExistence(timeout: 10))
    }
    app.activate()
    app.buttons["试用键盘"].tap()
    let onboarding = app.buttons.matching(NSPredicate(format: "label IN %@", ["Continue", "继续"])).firstMatch
    if onboarding.waitForExistence(timeout: 2) { onboarding.tap() }
    if !waitVisible(app.buttons["keyboardMode.帮你回"], timeout: 3) {
      let next = app.buttons.matching(NSPredicate(format: "label IN %@", ["Next keyboard", "下一个键盘", "下一键盘"])).firstMatch
      if next.exists { next.press(forDuration: 1) }
      let choice = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "恋爱键盘")).firstMatch
      if choice.exists { choice.tap() }
    }
    if !waitVisible(app.buttons["keyboardMode.帮你回"], timeout: 2), app.textViews["trialInput"].exists {
      app.textViews["trialInput"].tap()
    }
    XCTAssertTrue(waitVisible(app.buttons["keyboardMode.帮你回"], timeout: 10), app.debugDescription)
    return app
  }
  private func waitVisible(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: element)], timeout: timeout) == .completed
  }
  private func assertHost(_ app: XCUIApplication, _ text: String) {
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: app.textViews["trialInput"])], timeout: 5), .completed, app.debugDescription)
  }
  private func capture(_ name: String, _ app: XCUIApplication) {
    let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
  }
  private func requestReply(_ app: XCUIApplication) {
    app.buttons["keyboardMode.帮你回"].tap()
    app.buttons["+  粘贴TA的话"].tap()
    XCTAssertTrue(app.staticTexts["允许 AI 处理本次内容？"].waitForExistence(timeout: 3), "完全访问下首次点击必须留在键盘内征求授权")
    XCTAssertTrue(app.buttons["keyboardMode.键盘"].isHittable)
    app.buttons["keyboardPromptPrimary"].tap()
  }
  func testFullAccessReplyAndSuperSpeakActualButtons() {
    let app = launch("success")
    app.buttons["MNO"].tap(); app.buttons["GHI"].tap(); app.buttons["你"].tap()
    assertHost(app, "你")
    if !app.buttons["keyboardMode.帮你回"].isHittable && app.buttons["×"].exists { app.buttons["×"].tap() }
    app.buttons["keyboardMode.帮你回"].tap()
    app.buttons["+  粘贴TA的话"].tap()
    XCTAssertTrue(app.buttons["keyboardPromptDismiss"].waitForExistence(timeout: 3))
    capture("AI-完全访问-键盘内授权", app)
    app.buttons["keyboardPromptDismiss"].tap()
    XCTAssertTrue(app.buttons["+  粘贴TA的话"].isHittable)
    app.buttons["+  粘贴TA的话"].tap(); app.buttons["keyboardPromptPrimary"].tap()
    XCTAssertTrue(waitVisible(app.buttons["第一条回复"]))
    capture("AI-帮你回-三条返回", app)
    app.buttons["第一条回复"].tap(); assertHost(app, "你第一条回复")
    app.buttons["第二条回复"].tap(); assertHost(app, "你第二条回复")
    app.buttons["keyboardMode.超会说"].tap()
    app.buttons["✨ 优化"].tap()
    XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "请先输入想要优化的话")).firstMatch.waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["MNO"].isHittable)
    app.buttons["MNO"].tap(); app.buttons["GHI"].tap(); app.buttons["你"].tap()
    assertHost(app, "你第二条回复")
    app.buttons["✨ 优化"].tap()
    XCTAssertTrue(waitVisible(app.buttons["第一条话术"]))
    capture("AI-超会说-三条返回", app)
    app.buttons["第一条话术"].tap(); assertHost(app, "你第二条回复第一条话术")
    app.buttons["第二条话术"].tap(); assertHost(app, "你第二条回复第二条话术")
    app.buttons["keyboardMode.键盘"].tap()
    for _ in 0..<3 {
      app.buttons["⌄"].tap()
      XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == false"), object: app.buttons["keyboardMode.帮你回"])], timeout: 5), .completed)
      XCTAssertTrue(waitVisible(app.buttons["试用键盘"]))
      app.buttons["试用键盘"].tap()
      XCTAssertTrue(waitVisible(app.buttons["keyboardMode.帮你回"]))
    }
  }
  func testFullAccessServerErrorStaysInsideKeyboard() {
    let app = launch("failure")
    requestReply(app)
    XCTAssertTrue(app.staticTexts["模型服务暂不可用"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["测试服务暂不可用，请重试"].exists)
    XCTAssertTrue(app.buttons["keyboardMode.键盘"].isHittable)
    capture("AI-服务失败-扩展保留", app)
    XCTAssertTrue(app.buttons["检查配置"].isHittable)
    XCTAssertTrue(app.buttons["订阅套餐"].isHittable)
    XCTAssertFalse(app.buttons["重试生成"].exists)
    app.buttons["×"].tap()
    XCTAssertTrue(app.buttons["+  粘贴TA的话"].isHittable)
  }
  func testFullAccessTimeoutStaysInsideKeyboard() {
    let app = launch("timeout")
    requestReply(app)
    XCTAssertTrue(app.staticTexts["模型服务暂不可用"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["keyboardMode.超会说"].isHittable)
    capture("AI-超时-扩展保留", app)
  }
  func testScreenshotAndVoiceEntrypointsDoNotKillExtension() {
    let app = launch("no_model")
    app.buttons["keyboardSpace"].press(forDuration: 1)
    XCTAssertTrue(app.staticTexts["开启键盘语音"].waitForExistence(timeout: 3))
    app.buttons["keyboardVoiceCancel"].tap()
    XCTAssertTrue(app.buttons["keyboardMode.帮你回"].isHittable)
    app.buttons["keyboardMode.帮你回"].tap()
    app.buttons["📷  截图识别回复"].tap()
    let cancel = app.buttons["cancelKeyboardScreenshot"]
    // The remote keyboard height transition can outlive XCTest's idle check.
    // Re-query the visible destination after that transition before retrying.
    if !cancel.waitForExistence(timeout: 2) && app.buttons["replyScreenshot"].isHittable {
      app.buttons["replyScreenshot"].tap()
    }
    XCTAssertTrue(cancel.waitForExistence(timeout: 8), app.debugDescription)
    capture("AI-截图选择器", app)
    cancel.tap()
    XCTAssertTrue(waitVisible(app.buttons["keyboardMode.帮你回"]))
  }
  func testFullAccessNoModelAndOpenAppFallbackDoNotCrash() {
    let app = launch("no_model")
    requestReply(app)
    XCTAssertTrue(app.staticTexts["AI 功能还未开通"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["keyboardMode.键盘"].isHittable)
    app.buttons["配置模型"].tap()
    XCTAssertTrue(app.staticTexts["请打开恋爱键盘"].waitForExistence(timeout: 5) || app.staticTexts["大模型配置"].exists)
    capture("AI-未配置-主App引导", app)
  }
}


extension KeyboardAIFlowTests {
  func testLongPressSpaceTranscribesAndNeverOpensMainAppDialog() {
    let app = launch("success", voice: "success")
    app.buttons["MNO"].tap(); app.buttons["GHI"].tap(); app.buttons["你"].tap()
    app.buttons["keyboardSpace"].press(forDuration: 1)
    assertHost(app, "你明天一起吃饭。")
    capture("语音-空格松开自动回填", app)
    // A learned next-word strip temporarily replaces the mode header. Close it
    // before asserting mode navigation; it is still our keyboard throughout.
    if !app.buttons["keyboardMode.超会说"].isHittable && app.buttons["×"].exists { app.buttons["×"].tap() }
    XCTAssertTrue(waitVisible(app.buttons["keyboardMode.超会说"]))
    XCTAssertFalse(app.buttons["开启键盘语音"].exists)
    app.buttons["keyboardSpace"].press(forDuration: 1)
    assertHost(app, "你明天一起吃饭。明天一起吃饭。")
  }
  func testVoiceSuperSpeakDraftStaysInsideKeyboard() {
    let app = launch("success", voice: "success")
    app.buttons["keyboardMode.超会说"].tap()
    app.buttons["keyboardSpace"].press(forDuration: 1)
    XCTAssertTrue(waitVisible(app.buttons["aiDraftGenerate"]))
    XCTAssertTrue((app.staticTexts["keyboardAIDraft"].label).contains("明天一起吃饭"), app.debugDescription)
    assertHost(app, "")
    capture("语音-超会说内部草稿", app)
    XCTAssertFalse(app.buttons["aiDraftClear"].exists)
    XCTAssertFalse(app.buttons["aiDraftPaste"].exists)
    app.buttons["aiRelation.朋友"].tap()
    XCTAssertTrue(app.buttons["aiRelation.朋友"].isSelected)
    app.buttons["aiDraftGenerate"].tap()
    if app.buttons["keyboardPromptPrimary"].waitForExistence(timeout: 2) { app.buttons["keyboardPromptPrimary"].tap() }
    XCTAssertTrue(waitVisible(app.buttons["aiResult.0"]))
    XCTAssertFalse(app.buttons["aiRegenerate"].exists)
    XCTAssertFalse(app.buttons["aiBackToInput"].exists)
    XCTAssertFalse(app.buttons["aiReplyReanalyze"].exists)
    app.buttons["aiResult.0"].tap(); assertHost(app, "第一条话术")
    app.buttons["aiResultClose"].tap()
    XCTAssertTrue(app.staticTexts["keyboardAIDraft"].label.contains("明天一起吃饭"))
    app.buttons["aiDraftGenerate"].tap()
    XCTAssertTrue(waitVisible(app.buttons["aiResult.2"]))
    app.buttons["aiResultClose"].tap()
    XCTAssertTrue(app.staticTexts["keyboardAIDraft"].label.contains("明天一起吃饭"))
  }
  func testVoiceErrorAndNoSpeechReturnToKeyboard() {
    for scenario in ["failure", "empty"] {
      let app = launch("success", voice: scenario)
      app.buttons["keyboardSpace"].press(forDuration: 1)
      let message = scenario == "empty" ? "没有识别到语音，请重试" : "语音识别失败：测试识别服务暂不可用"
      XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", message), object: app.staticTexts["keyboardVoiceTranscript"])], timeout: 10), .completed)
      XCTAssertTrue(app.buttons["keyboardSpace"].isHittable)
      assertHost(app, "")
      app.buttons["keyboardVoiceCancel"].tap()
      XCTAssertTrue(waitVisible(app.buttons["keyboardMode.帮你回"]))
      app.terminate()
    }
  }
  func testReplyUsesOnlyAndroidPasteScreenshotReanalyzeAndCloseActions() {
    let app = launch("success")
    app.buttons["keyboardMode.帮你回"].tap()
    XCTAssertTrue(app.buttons["replyPaste"].isHittable)
    XCTAssertTrue(app.buttons["replyScreenshot"].isHittable)
    XCTAssertFalse(app.buttons["replyManualInput"].exists)
    XCTAssertFalse(app.buttons["手动输入TA的话"].exists)
    capture("安卓对照-帮你回-仅粘贴与截图", app)
    requestReply(app)
    XCTAssertTrue(waitVisible(app.buttons["aiResult.0"]))
    XCTAssertTrue(app.staticTexts["AI推荐回复（点击使用）"].exists)
    XCTAssertFalse(app.buttons["aiBackToInput"].exists)
    XCTAssertFalse(app.buttons["aiRegenerate"].exists)
    capture("安卓对照-帮你回-推荐与重新分析", app)
    app.buttons["aiResult.0"].tap(); assertHost(app, "第一条回复")
    app.buttons["aiResult.1"].tap(); assertHost(app, "第二条回复")
    app.buttons["aiReplyReanalyze"].tap()
    XCTAssertTrue(waitVisible(app.buttons["aiResult.2"]))
    app.buttons["aiResultClose"].tap()
    XCTAssertTrue(app.buttons["replyPaste"].isHittable)
    XCTAssertTrue(app.buttons["replyScreenshot"].isHittable)
    XCTAssertFalse(app.buttons["keyboardAIDraft"].exists)
    XCTAssertFalse(app.buttons["replyManualInput"].exists)
  }
  func testVoiceIsCancelledWhenHostKeyboardIsDismissed() {
    let app = launch("success", voice: "pending")
    for _ in 0..<3 {
      app.buttons["keyboardSpace"].press(forDuration: 1)
      XCTAssertTrue(app.buttons["keyboardVoiceCancel"].waitForExistence(timeout: 3))
      // Removing the host TextEditor must cancel the utterance and invalidate
      // its document before UIKit reconnects the next host input session.
      app.buttons["返回"].tap()
      XCTAssertTrue(app.staticTexts["让聊天更有爱 💕"].waitForExistence(timeout: 5))
      app.buttons["键盘"].tap()
      app.buttons["试用键盘"].tap()
      XCTAssertTrue(waitVisible(app.buttons["keyboardMode.键盘"]))
      assertHost(app, "")
    }
  }
}

extension KeyboardAIFlowTests {
  func testVoiceSpaceSlideUpCancelsWithoutInserting() {
    let app = launch("success", voice: "pending")
    let space = app.buttons["keyboardSpace"]
    let start = space.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    start.press(forDuration: 0.7, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -140)))
    XCTAssertTrue(waitVisible(app.buttons["keyboardMode.帮你回"]))
    assertHost(app, "")
    app.buttons["keyboardSpace"].press(forDuration: 1)
    XCTAssertTrue(app.buttons["keyboardVoiceCancel"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["MNO"].isHittable)
    app.buttons["keyboardVoiceCancel"].tap()
    XCTAssertTrue(waitVisible(app.buttons["keyboardMode.键盘"]))
    assertHost(app, "")
  }
}

extension KeyboardAIFlowTests {
  func testReplyLoadingCloseCancelsAndThreeResultsUseAndroidActions() {
    var app = launch("slow")
    requestReply(app)
    XCTAssertTrue(app.buttons["aiResultClose"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.buttons["取消生成"].exists)
    app.buttons["aiResultClose"].tap()
    XCTAssertTrue(waitVisible(app.buttons["replyPaste"]))
    assertHost(app, "")
    XCTAssertFalse(app.buttons["aiResult.0"].exists)
    app.terminate()
    app = launch("long")
    requestReply(app)
    XCTAssertTrue(waitVisible(app.buttons["aiResult.0"]))
    XCTAssertGreaterThan(app.buttons["aiResult.0"].label.count, 100)
    for index in 0..<3 { XCTAssertTrue(app.buttons["aiResult.\(index)"].isHittable) }
    capture("安卓对照-三条回复与关闭", app)
    let third = app.buttons["aiResult.2"]
    let text = third.label
    third.tap(); assertHost(app, text)
    app.buttons["aiResultClose"].tap()
    XCTAssertTrue(app.buttons["replyPaste"].isHittable)
    XCTAssertFalse(app.buttons["keyboardAIDraft"].exists)
  }
}

extension KeyboardAIFlowTests {
  func testScreenshotSelectionActuallyGeneratesAndInsertsReply() {
    let app = launch("success")
    app.buttons["keyboardMode.帮你回"].tap()
    app.buttons["replyScreenshot"].tap()
    XCTAssertTrue(app.buttons["cancelKeyboardScreenshot"].waitForExistence(timeout: 8), app.debugDescription)
    let photo = app.images.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "截屏", "Screenshot")).firstMatch
    XCTAssertTrue(photo.waitForExistence(timeout: 8), app.debugDescription)
    let cancelFrame = app.buttons["cancelKeyboardScreenshot"].frame
    if photo.isHittable && photo.frame.minY >= cancelFrame.maxY { photo.tap() }
    else {
      // iOS 27 reports the remote Photos grid in local coordinates. The first
      // thumbnail is visibly below the selector's header; anchor to our actual
      // cancel control when Photos cannot supply a screen activation point.
      app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width/6, dy: cancelFrame.maxY+74)).tap()
    }
    XCTAssertTrue(app.buttons["keyboardPromptPrimary"].waitForExistence(timeout: 8), app.debugDescription)
    app.buttons["keyboardPromptPrimary"].tap()
    XCTAssertTrue(waitVisible(app.buttons["aiResult.0"]), app.debugDescription)
    capture("AI-实际选图后生成回复", app)
    XCTAssertEqual(app.buttons["aiResult.0"].label, "第一条截图回复")
    app.buttons["aiResult.0"].tap(); assertHost(app, "第一条截图回复")
  }
}


extension KeyboardAIFlowTests {
  func testVoiceRecognitionAreaPreservesKeyboardCoordinates() {
    let app = launch("success", voice: "pending")
    defer { XCUIDevice.shared.orientation = .portrait }
    for (mode, orientation) in [("键盘", UIDeviceOrientation.portrait), ("键盘", .landscapeLeft), ("超会说", .portrait)] {
      XCUIDevice.shared.orientation = orientation
      XCTAssertTrue(waitVisible(app.buttons["keyboardSpace"]))
      app.buttons["keyboardMode." + mode].tap()
      let keys = ["keyboardSpace", "MNO", "GHI", "keyboardEnter"]
      let before = keys.map { app.buttons[$0].frame }
      app.buttons["keyboardSpace"].press(forDuration: 1)
      XCTAssertTrue(app.staticTexts["keyboardVoiceTranscript"].waitForExistence(timeout: 3))
      XCTAssertTrue(app.buttons["keyboardMode." + mode].isHittable, "语音不能切换或遮盖当前面板")
      for (index, name) in keys.enumerated() {
        let frame = app.buttons[name].frame
        print("VOICE_GEOMETRY \(mode) \(orientation.rawValue) \(name): \(before[index]) -> \(frame)")
        XCTAssertEqual(frame.minX, before[index].minX, accuracy: 1, name)
        XCTAssertEqual(frame.minY, before[index].minY, accuracy: 1, name)
        XCTAssertEqual(frame.width, before[index].width, accuracy: 1, name)
        XCTAssertEqual(frame.height, before[index].height, accuracy: 1, name)
      }
      XCTAssertLessThan(app.staticTexts["keyboardVoiceTranscript"].frame.maxY, app.buttons["GHI"].frame.minY)
      capture("语音-顶部识别区-\(mode)-\(orientation.rawValue)", app)
      app.buttons["keyboardVoiceCancel"].tap()
      XCTAssertTrue(waitVisible(app.buttons["keyboardSpace"]))
      for (index, name) in keys.enumerated() {
        XCTAssertEqual(app.buttons[name].frame.minY, before[index].minY, accuracy: 1, "取消后按键位置：" + name)
      }
      assertHost(app, "")
    }
  }
}

extension KeyboardAIFlowTests {
  func testVoiceCanStartDuringPinyinWithoutLosingHeldSpace() {
    let app = launch("success", voice: "pending")
    app.buttons["MNO"].tap(); app.buttons["GHI"].tap()
    XCTAssertTrue(app.buttons["你"].waitForExistence(timeout: 3))
    let before = app.buttons["keyboardSpace"].frame
    app.buttons["keyboardSpace"].press(forDuration: 1)
    XCTAssertTrue(app.staticTexts["keyboardVoiceTranscript"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["GHI"].isHittable)
    XCTAssertEqual(app.buttons["keyboardSpace"].frame.minY, before.minY, accuracy: 1)
    capture("语音-拼音组合中长按仍保持空格", app)
    app.buttons["keyboardVoiceCancel"].tap()
    assertHost(app, "你")
  }
}

extension KeyboardAIFlowTests {
  func testMainAppKnowledgeChangesAreSharedWithKeyboard() {
    let app = launch("success")
    func openKnowledge() {
      app.buttons["返回"].tap()
      XCTAssertTrue(app.staticTexts["让聊天更有爱 💕"].waitForExistence(timeout: 3))
      XCTAssertTrue(waitVisible(app.buttons["知识库"]))
      app.buttons["知识库"].tap()
      if !app.buttons["knowledgeAdd"].waitForExistence(timeout: 2) { app.buttons["知识库"].tap() }
      XCTAssertTrue(app.buttons["knowledgeAdd"].waitForExistence(timeout: 4), app.debugDescription)
    }
    openKnowledge()
    app.buttons["knowledgeAdd"].tap(); app.buttons["新建文档"].tap()
    let title = "键盘联动 " + String(UUID().uuidString.prefix(6))
    app.textFields["knowledgeTitle"].tap(); app.textFields["knowledgeTitle"].typeText(title)
    app.textViews["knowledgeBody"].tap(); app.textViews["knowledgeBody"].typeText("# 邀约\n给对方准备时间，用自然低压力的语气表达。")
    app.buttons["knowledgeSave"].tap()
    let document = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "knowledgeDocument.", title)).firstMatch
    XCTAssertTrue(document.waitForExistence(timeout: 4), app.debugDescription)
    let moreID = document.identifier.replacingOccurrences(of: "knowledgeDocument.", with: "knowledgeMore.")
    app.buttons[moreID].tap(); app.buttons["设为默认"].tap()
    func openKeyboard() {
      app.buttons["键盘"].tap(); app.buttons["试用键盘"].tap()
      if !waitVisible(app.buttons["keyboardMode.帮你回"], timeout: 2) { app.textViews["trialInput"].tap() }
      XCTAssertTrue(waitVisible(app.buttons["keyboardMode.帮你回"]))
      app.buttons["keyboardMode.帮你回"].tap()
    }
    openKeyboard(); requestReply(app)
    XCTAssertTrue(waitVisible(app.buttons["aiResult.0"]))
    XCTAssertTrue(app.buttons["aiKnowledge"].label.contains(title))
    app.buttons["aiKnowledge"].tap()
    XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 3))
    app.buttons[title].tap()
    openKnowledge()
    app.buttons[moreID].tap(); app.buttons["停用"].tap()
    openKeyboard(); app.buttons["replyPaste"].tap()
    XCTAssertTrue(waitVisible(app.buttons["aiResult.0"]))
    XCTAssertTrue(app.buttons["aiKnowledge"].label.contains("未选择知识库"))
    app.buttons["aiKnowledge"].tap()
    XCTAssertFalse(app.buttons[title].exists)
    app.buttons["狗头军师知识库"].tap()
    capture("知识库-停用文档不再进入键盘选择", app)
    openKnowledge()
    app.buttons[moreID].tap(); app.buttons["删除文档"].tap(); app.alerts.buttons["删除"].tap()
    app.buttons["knowledgeMore.builtin-goutoujunshi-v1"].tap(); app.buttons["设为默认"].tap()
  }
  func testSuperSpeakWriteNewContentClearsOnlyLocalDraft() {
    let app = launch("success")
    app.buttons["keyboardMode.超会说"].tap()
    app.buttons["t9Key.6"].tap(); app.buttons["t9Key.4"].tap(); app.buttons["你"].tap()
    app.buttons["aiDraftGenerate"].tap()
    if app.buttons["keyboardPromptPrimary"].waitForExistence(timeout: 2) { app.buttons["keyboardPromptPrimary"].tap() }
    XCTAssertTrue(waitVisible(app.buttons["aiResult.0"]))
    XCTAssertTrue(app.buttons["aiNewContent"].isHittable)
    app.buttons["aiResult.0"].tap()
    assertHost(app, "第一条话术")
    app.buttons["aiNewContent"].tap()
    XCTAssertTrue(waitVisible(app.buttons["aiDraftGenerate"]))
    XCTAssertFalse(app.buttons["aiResult.0"].exists)
    XCTAssertEqual(app.staticTexts["keyboardAIDraft"].label, "输入你想说的话，AI帮你优化")
    assertHost(app, "第一条话术")
    app.buttons["t9Key.6"].tap(); app.buttons["t9Key.4"].tap(); app.buttons["你"].tap()
    XCTAssertTrue(app.staticTexts["keyboardAIDraft"].label.contains("你"))
    assertHost(app, "第一条话术")
    capture("安卓对齐-超会说-写新内容", app)
  }
  func testKnowledgeSelectionInvalidatesResultsAndKeepsHostText() {
    let app = launch("success")
    requestReply(app)
    XCTAssertTrue(waitVisible(app.buttons["aiResult.0"]))
    app.buttons["aiResult.0"].tap()
    assertHost(app, "第一条回复")
    app.buttons["aiKnowledge"].tap()
    let none = app.buttons["未选择知识库"]
    XCTAssertTrue(none.waitForExistence(timeout: 3), app.debugDescription)
    none.tap()
    XCTAssertTrue(waitVisible(app.buttons["replyPaste"]))
    XCTAssertFalse(app.buttons["aiResult.0"].exists)
    assertHost(app, "第一条回复")
    app.buttons["replyPaste"].tap()
    XCTAssertTrue(waitVisible(app.buttons["aiResult.0"]))
    XCTAssertTrue(app.buttons["aiKnowledge"].label.contains("未选择知识库"))
    app.buttons["aiKnowledge"].tap()
    app.buttons["狗头军师知识库"].tap()
    XCTAssertTrue(waitVisible(app.buttons["replyPaste"]))
  }
}
