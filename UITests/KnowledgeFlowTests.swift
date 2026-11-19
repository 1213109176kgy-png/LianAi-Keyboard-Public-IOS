import XCTest

@MainActor
final class KnowledgeFlowTests: XCTestCase {
  nonisolated override func setUpWithError() throws { continueAfterFailure = false }
  private func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["LIANAI_PREVIEW_PAGE"] = "home"
    app.launch()
    XCTAssertTrue(app.buttons["知识库"].waitForExistence(timeout: 10))
    app.buttons["知识库"].tap()
    XCTAssertTrue(app.buttons["knowledgeAdd"].waitForExistence(timeout: 5))
    return app
  }
  private func capture(_ name: String, _ app: XCUIApplication) {
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = name; image.lifetime = .keepAlways; add(image)
  }
  private func row(_ title: String, _ app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "knowledgeDocument.", title)).firstMatch
  }
  private func more(_ row: XCUIElement, _ app: XCUIApplication) -> XCUIElement {
    app.buttons[row.identifier.replacingOccurrences(of: "knowledgeDocument.", with: "knowledgeMore.")]
  }
  func testFourTabsBuiltInReadingAndProtectedMenus() {
    let app = launch()
    for title in ["首页", "键盘", "知识库", "我的"] { XCTAssertTrue(app.buttons[title].isHittable) }
    let builtin = app.buttons["knowledgeDocument.builtin-goutoujunshi-v1"]
    XCTAssertTrue(builtin.exists)
    XCTAssertTrue(app.buttons["knowledgeDocument.builtin-tong-jincheng-v1"].exists)
    capture("iOS-知识库-文档列表", app)
    app.buttons["knowledgeMore.builtin-goutoujunshi-v1"].tap()
    XCTAssertFalse(app.buttons["删除文档"].exists)
    XCTAssertFalse(app.buttons["编辑文档"].exists)
    app.buttons["停用"].tap()
    XCTAssertTrue(builtin.label.contains("已停用"))
    app.buttons["knowledgeMore.builtin-goutoujunshi-v1"].tap()
    app.buttons["设为默认"].tap()
    XCTAssertTrue(builtin.label.contains("默认"))
    XCTAssertTrue(builtin.label.contains("已启用"))
    builtin.tap()
    XCTAssertTrue(app.buttons["knowledgeBack"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["knowledgeEdit"].exists)
    XCTAssertFalse(app.buttons["知识库"].exists, "阅读详情与安卓一样隐藏底栏")
    XCTAssertTrue(app.staticTexts["狗头军师知识库"].waitForExistence(timeout: 5))
    capture("iOS-知识库-内置阅读", app)
    app.buttons["knowledgeBack"].tap()
    XCTAssertTrue(app.buttons["知识库"].waitForExistence(timeout: 3))
  }
  func testCustomDocumentLifecycleSearchAndUnsavedProtection() {
    let app = launch()
    let title = "验收文档 " + String(UUID().uuidString.prefix(6))
    app.buttons["knowledgeAdd"].tap(); app.buttons["新建文档"].tap()
    capture("iOS-知识库-空白编辑", app)
    app.buttons["knowledgeSave"].tap()
    XCTAssertTrue(app.staticTexts["请输入1–120字标题"].waitForExistence(timeout: 3))
    app.textFields["knowledgeTitle"].tap(); app.textFields["knowledgeTitle"].typeText(title)
    app.textViews["knowledgeBody"].tap()
    app.textViews["knowledgeBody"].typeText("# 邀约资料\n只在正文能找到的标记\n\n| 场景 | 方法 |\n| --- | --- |\n| 邀约 | 留出准备时间，低压力表达，尊重对方边界 |")
    capture("iOS-知识库-新建编辑", app)
    app.buttons["knowledgeBack"].tap()
    XCTAssertTrue(app.alerts["放弃未保存的修改？"].waitForExistence(timeout: 3))
    app.buttons["继续编辑"].tap()
    app.buttons["knowledgeSave"].tap()
    let document = row(title, app)
    XCTAssertTrue(document.waitForExistence(timeout: 5), app.debugDescription)
    let search = app.textFields["knowledgeSearch"]
    search.tap(); search.typeText("只在正文能找到的标记")
    XCTAssertEqual(app.staticTexts["knowledgeCount"].label, "全部文档 · 1 份")
    document.tap()
    XCTAssertTrue(app.staticTexts["邀约资料"].waitForExistence(timeout: 4))
    capture("iOS-知识库-Markdown与表格", app)
    app.buttons["knowledgeEdit"].tap()
    app.textViews["knowledgeBody"].tap(); app.textViews["knowledgeBody"].typeText("\n保存后的新内容")
    app.buttons["knowledgeSave"].tap()
    more(document, app).tap(); app.buttons["停用"].tap()
    XCTAssertTrue(document.label.contains("已停用"))
    more(document, app).tap(); app.buttons["设为默认"].tap()
    XCTAssertTrue(document.label.contains("默认")); XCTAssertTrue(document.label.contains("已启用"))
    capture("iOS-知识库-搜索和默认文档", app)
    more(document, app).tap(); app.buttons["删除文档"].tap()
    app.alerts.buttons["取消"].tap(); XCTAssertTrue(document.exists)
    more(document, app).tap(); app.buttons["删除文档"].tap()
    app.alerts.buttons["删除"].tap()
    XCTAssertFalse(document.exists)
    XCTAssertTrue(app.staticTexts["没有匹配的文档"].waitForExistence(timeout: 3))
    app.terminate()
    let restored = launch()
    XCTAssertFalse(row(title, restored).exists)
    restored.buttons["knowledgeMore.builtin-goutoujunshi-v1"].tap(); restored.buttons["设为默认"].tap()
    restored.buttons["knowledgeAdd"].tap(); restored.buttons["新建文档"].tap()
    restored.textFields["knowledgeTitle"].tap(); restored.textFields["knowledgeTitle"].typeText("放弃的资料")
    restored.buttons["knowledgeBack"].tap(); restored.buttons["放弃"].tap()
    XCTAssertFalse(row("放弃的资料", restored).exists)
  }
  func testLocalMarkdownImportUsesRealDocumentPicker() {
    let app = launch()
    app.buttons["knowledgeAdd"].tap(); app.buttons["导入本机文档"].tap()
    let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "取消"])).firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: 8), app.debugDescription)
    capture("iOS-知识库-系统文件选择器", app)
    // The fixture is a benign Markdown file copied into this isolated app's
    // Documents folder before the run, visible via the native Files provider.
    let browse = app.buttons.matching(NSPredicate(format: "label IN %@", ["Browse", "浏览"])).firstMatch
    if browse.exists { browse.tap() }
    let phone = app.cells.matching(NSPredicate(format: "label IN %@", ["On My iPhone", "我的 iPhone", "我的iPhone"])).firstMatch
    for _ in 0..<6 {
      if phone.exists { break }
      let back = app.buttons["DOC.navBarButton.backInHistory"]
      if back.exists && back.isEnabled { back.tap() }
      else if browse.exists { browse.tap() }
    }
    XCTAssertTrue(phone.waitForExistence(timeout: 3), app.debugDescription)
    phone.tap()
    let folder = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "恋爱键盘")).firstMatch
    if folder.waitForExistence(timeout: 3) { folder.tap() }
    let file = app.collectionViews["File View"].cells.matching(NSPredicate(format: "label CONTAINS %@", "知识库导入验收")).firstMatch
    XCTAssertTrue(file.waitForExistence(timeout: 5), app.debugDescription)
    file.tap()
    XCTAssertTrue(app.textFields["knowledgeTitle"].waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertEqual(app.textFields["knowledgeTitle"].value as? String, "知识库导入验收")
    XCTAssertTrue((app.textViews["knowledgeBody"].value as? String ?? "").contains("导入的完整正文"))
    capture("iOS-知识库-导入待保存", app)
    app.buttons["knowledgeSave"].tap()
    let document = row("知识库导入验收", app)
    XCTAssertTrue(document.waitForExistence(timeout: 3))
    more(document, app).tap(); app.buttons["删除文档"].tap()
    capture("iOS-知识库-导入后删除确认", app)
    XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    app.alerts.buttons["删除"].tap()
  }
}
