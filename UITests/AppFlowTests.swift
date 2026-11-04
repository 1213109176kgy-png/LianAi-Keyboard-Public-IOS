import XCTest

@MainActor
final class AppFlowTests: XCTestCase {
  nonisolated override func setUpWithError() throws { continueAfterFailure = false }
  private func launch(_ page: String = "home") -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["LIANAI_PREVIEW_PAGE"] = page
    app.launch()
    XCTAssertTrue(app.buttons["我的"].waitForExistence(timeout: 10))
    return app
  }
  private func capture(_ name: String, _ app: XCUIApplication) {
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = name
    image.lifetime = .keepAlways
    add(image)
  }
  func testNavigationSettingsAndLoginValidation() {
    let app = launch()
    XCTAssertTrue(app.staticTexts["让聊天更有爱 💕"].exists)
    capture("01-首页", app)
    app.buttons["我的"].tap()
    app.buttons.containing(.staticText, identifier: "设置").firstMatch.tap()
    XCTAssertTrue(app.staticTexts["键盘设置"].waitForExistence(timeout: 3))
    capture("02-设置", app)
    app.buttons.containing(.staticText, identifier: "布局和显示").firstMatch.tap()
    XCTAssertTrue(app.staticTexts["候选词大小"].waitForExistence(timeout: 3))
    capture("03-布局和显示", app)
    app.buttons["返回"].tap()
    app.buttons["我的"].tap()
    app.buttons.containing(.staticText, identifier: "未登录").firstMatch.tap()
    app.buttons["登录"].tap()
    XCTAssertTrue(app.staticTexts["请输入正确的 11 位手机号"].waitForExistence(timeout: 3))
    capture("04-登录校验", app)
  }
  func testConfigurationChoosersSaveAndRestore() {
    let app = launch("management")
    app.buttons["每次调出默认模式"].tap()
    XCTAssertTrue(app.buttons["英文"].waitForExistence(timeout: 3))
    capture("配置-默认模式选择", app)
    app.buttons["英文"].tap()
    XCTAssertTrue(app.buttons["每次调出默认模式"].label.contains("英文"))
    app.buttons["每次调出默认模式"].tap()
    app.buttons["拼音"].tap()
    app.terminate()
    let models = launch("models")
    models.buttons.containing(.staticText, identifier: "不想订阅？使用自定义模型").firstMatch.tap()
    let provider = models.buttons["模型服务商"]
    if !provider.isHittable { models.swipeUp() }
    provider.tap()
    XCTAssertTrue(models.buttons["智谱"].waitForExistence(timeout: 3))
    capture("配置-六家模型服务商", models)
    models.buttons["DeepSeek"].tap()
    XCTAssertTrue(models.buttons["模型服务商"].label.contains("DeepSeek"))
    XCTAssertTrue(models.staticTexts["官方接口：https://api.deepseek.com/v1"].exists)
    models.buttons["模型服务商"].tap()
    models.buttons["自定义模型"].tap()
  }
  func testThemeSwitchRendersAppAndRealKeyboard() {
    let app = launch("layout")
    app.buttons["暗黑模式"].tap()
    capture("主题-暗色布局", app)
    app.buttons["键盘"].tap()
    app.buttons["试用键盘"].tap()
    let visible = NSPredicate(format: "exists == true AND hittable == true")
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: app.buttons["MNO"])], timeout: 10), .completed)
    capture("主题-暗色真实键盘", app)
    app.terminate()
    let restored = launch("layout")
    restored.buttons["亮色模式"].tap()
    capture("主题-恢复亮色布局", restored)
  }
  func testAboutUsesAndroidActionsWithoutExtraDisclosure() {
    let app = launch("about")
    XCTAssertTrue(app.staticTexts["关于我们"].exists)
    XCTAssertTrue(app.buttons.containing(.staticText, identifier: "版本信息").firstMatch.exists)
    XCTAssertTrue(app.buttons.containing(.staticText, identifier: "隐私政策").firstMatch.exists)
    app.swipeUp()
    XCTAssertTrue(app.staticTexts["随缘打赏"].exists)
    XCTAssertFalse(app.buttons["第三方开源许可"].exists)
    XCTAssertFalse(app.links["查看项目源码"].exists)
    capture("安卓对照-关于页无额外入口", app)
    app.buttons["返回"].tap()
    XCTAssertTrue(app.staticTexts["个人中心"].waitForExistence(timeout: 3))
  }
  func testAllSecondaryPagesRenderAndReturn() {
    for (page, title) in [
      ("profile", "个人中心"), ("test", "键盘试用"), ("settings", "设置"), ("layout", "布局和显示"), ("effects", "按键效果"), ("auxiliary", "辅助输入"), ("management", "键盘管理"),
      ("models", "大模型配置"), ("optimize", "优化输入"), ("clipboard", "剪贴板"),
      ("data", "本机数据"), ("permissions", "权限管理"), ("guide", "使用指引"),
      ("about", "关于我们"), ("subscription", "订阅套餐"),
    ] {
      let app = launch(page)
      XCTAssertTrue(app.staticTexts[title].exists, title)
      if page == "subscription" {
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["正在加载套餐…"])], timeout: 25)
      }
      if page == "data" { XCTAssertFalse(app.buttons["撤销 AI 内容处理授权"].exists) }
      if page == "test" { XCTAssertFalse(app.buttons["启用与切换指引"].exists) }
      if page == "about" {
        XCTAssertFalse(app.buttons["第三方开源许可"].exists)
        XCTAssertFalse(app.links["查看项目源码"].exists)
      }
      capture("页面-" + title, app)
      if page == "profile" { app.buttons["首页"].tap() } else { app.buttons["返回"].tap() }
      let parent = ["profile", "test"].contains(page) ? "让聊天更有爱 💕" : ["guide", "about", "subscription", "settings"].contains(page) ? "个人中心" : "设置"
      XCTAssertTrue(app.staticTexts[parent].waitForExistence(timeout: 3), page + " -> " + parent)
      app.terminate()
    }
  }
}
