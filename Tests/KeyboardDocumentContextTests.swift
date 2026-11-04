import Foundation
import XCTest
@testable import LianAiKeyboard

@MainActor
final class KeyboardDocumentContextTests: XCTestCase {
  private final class DisconnectableProxy: NSObject {
    @objc dynamic var documentIdentifier: NSUUID?
  }
  func testNilHostIdentifierDoesNotInvokeUnconditionalUUIDBridge() {
    let proxy = DisconnectableProxy()
    XCTAssertNil(KeyboardDocumentContext.identifier(of: proxy))
    let id = UUID()
    proxy.documentIdentifier = id as NSUUID
    XCTAssertEqual(KeyboardDocumentContext.identifier(of: proxy), id)
    proxy.documentIdentifier = nil
    XCTAssertNil(KeyboardDocumentContext.identifier(of: proxy))
  }
  func testUnknownProxyHasNoIdentity() {
    XCTAssertNil(KeyboardDocumentContext.identifier(of: NSObject()))
  }
}
