import XCTest
@testable import LianAiCore

@MainActor
final class AppStoreUpdateTests: XCTestCase {
  func testConfiguredAppleIDOpensItsPageWithoutCatalogRequest() async throws {
    let transport = FixtureTransport("", status: 503)
    let url = try await AppStoreUpdate.pageURL(bundleID: "com.lianai.keyboard.ios",
      configuredID: "1234567890", country: "CN", transport: transport)
    XCTAssertEqual(url.absoluteString, "https://apps.apple.com/app/id1234567890")
    let request = await transport.last()
    XCTAssertNil(request)
    for invalid in ["", "0", "１２３", "123/other", "https://example.com", "-1"] {
      XCTAssertNil(AppStoreUpdate.pageURL(appID: invalid))
    }
  }

  func testCatalogSelectsExactBundleAndNeverUsesAnUntrustedPageURL() async throws {
    let transport = FixtureTransport(#"{"results":[{"bundleId":"other.app","trackId":111},{"bundleId":"com.lianai.keyboard.ios","trackId":222,"trackViewUrl":"https://example.com/download.apk"}]}"#)
    let url = try await AppStoreUpdate.pageURL(bundleID: "com.lianai.keyboard.ios",
      configuredID: nil, country: "CN", transport: transport)
    XCTAssertEqual(url.absoluteString, "https://apps.apple.com/app/id222")
    let captured = await transport.last()
    let request = try XCTUnwrap(captured)
    XCTAssertEqual(request.url?.host, "itunes.apple.com")
    let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
    XCTAssertEqual(query?.first(where: { $0.name == "bundleId" })?.value, "com.lianai.keyboard.ios")
    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
  }

  func testMissingOrUnrelatedListingDoesNotPretendAppIsUpToDate() async throws {
    for body in [#"{"results":[]}"#,
      #"{"results":[{"bundleId":"other.app","trackId":111}]}"#,
      #"{"results":[{"bundleId":"com.lianai.keyboard.ios"}]}"#] {
      do {
        _ = try await AppStoreUpdate.pageURL(bundleID: "com.lianai.keyboard.ios",
          configuredID: nil, country: "CN", transport: FixtureTransport(body))
        XCTFail("Missing listing must not yield a download destination")
      } catch {
        XCTAssertEqual(error.localizedDescription, "暂未找到此应用的 App Store 页面，请稍后重试")
      }
    }
  }

  func testCatalogFailureCannotBecomeAnUpgradeDestination() async throws {
    for (body, status) in [("{}", 503), ("not JSON", 200)] {
      do {
        _ = try await AppStoreUpdate.pageURL(bundleID: "com.lianai.keyboard.ios",
          configuredID: nil, country: "CN", transport: FixtureTransport(body, status: status))
        XCTFail("Failed response must not yield a download destination")
      } catch {}
    }
  }
}
