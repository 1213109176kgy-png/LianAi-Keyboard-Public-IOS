import XCTest
@testable import LianAiKeyboard

@MainActor
final class NavigationTests: XCTestCase {
  func testEveryPageUsesAndroidParentInsteadOfVisitHistory() {
    let expected: [Page: Page] = [
      .home: .home, .profile: .home, .test: .home,
      .subscription: .profile, .settings: .profile, .about: .profile, .guide: .profile,
      .layout: .settings, .effects: .settings, .auxiliary: .settings,
      .management: .settings, .optimize: .settings, .clipboard: .settings,
      .data: .settings, .permissions: .settings,
    ]
    for (page, parent) in expected {
      let model = AppModel()
      model.tab(.test)
      model.navigate(page)
      model.back()
      XCTAssertEqual(model.page, parent, page.rawValue)
    }
  }
  func testModelPageRemembersOnlyItsTwoAndroidEntryPoints() {
    let model = AppModel()
    model.navigate(.models)
    model.back()
    XCTAssertEqual(model.page, .home)
    model.tab(.settings)
    model.navigate(.models)
    model.navigate(.subscription)
    model.back()
    XCTAssertEqual(model.page, .profile)
    model.tab(.models)
    model.back()
    XCTAssertEqual(model.page, .settings)
  }
}
