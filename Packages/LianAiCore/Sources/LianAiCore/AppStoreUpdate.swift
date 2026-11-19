import Foundation

public enum AppStoreUpdate {
  public static func pageURL(appID: String) -> URL? {
    guard !appID.isEmpty, appID.allSatisfy({ $0.isASCII && $0.isNumber }),
      let number = UInt64(appID), number > 0
    else { return nil }
    return URL(string: "https://apps.apple.com/app/id\(number)")
  }

  /// A configured Apple ID opens immediately. Before it is configured, resolve
  /// the exact bundle identifier from Apple's public catalog after publication.
  public static func pageURL(
    bundleID: String, configuredID: String?, country: String,
    transport: any HTTPTransport = URLSessionTransport()
  ) async throws -> URL {
    if let configuredID, let url = pageURL(appID: configuredID) { return url }
    var lookup = URLComponents(string: "https://itunes.apple.com/lookup")!
    lookup.queryItems = [URLQueryItem(name: "bundleId", value: bundleID),
      URLQueryItem(name: "country", value: country)]
    var request = URLRequest(url: lookup.url!)
    request.timeoutInterval = 15
    request.cachePolicy = .reloadIgnoringLocalCacheData
    let (data, response) = try await transport.data(for: request)
    guard (200..<300).contains(response.statusCode) else {
      throw ClientError.message("暂时无法连接 App Store，请稍后重试")
    }
    struct Result: Decodable { var bundleId: String?; var trackId: UInt64? }
    struct Response: Decodable { var results: [Result] }
    let result = try JSONDecoder().decode(Response.self, from: data)
    guard let app = result.results.first(where: { $0.bundleId == bundleID }),
      let id = app.trackId, let url = pageURL(appID: String(id))
    else { throw ClientError.message("暂未找到此应用的 App Store 页面，请稍后重试") }
    return url
  }
}
