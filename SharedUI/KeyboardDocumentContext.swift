import Foundation
import UIKit

@MainActor
enum KeyboardDocumentContext {
  // Call only while the host input session is active. A nullable bridge cannot
  // make UIKit's previous, disconnected proxy valid during viewWillAppear.
  static func identifier(of proxy: NSObject) -> UUID? {
    // UIKit can return nil while the host disconnects, although the imported
    // Swift property is nonoptional UUID. Read the public Objective-C getter
    // through its nullable KVC result to avoid UUID's unconditional bridge trap.
    let key = #keyPath(UITextDocumentProxy.documentIdentifier)
    guard proxy.responds(to: NSSelectorFromString(key)) else { return nil }
    return proxy.value(forKey: key) as? UUID
  }
}
