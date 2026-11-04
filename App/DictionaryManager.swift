import Combine
import CryptoKit
import Foundation
import LianAiCore

final class DictionaryProgress: NSObject, URLSessionDownloadDelegate, Sendable {
  let report: @Sendable (Double) -> Void
  init(report: @escaping @Sendable (Double) -> Void) { self.report = report }
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {}
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    if totalBytesExpectedToWrite > 0 {
      report(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
  }
}
@MainActor
final class DictionaryManager: ObservableObject {
  static let shared = DictionaryManager()
  @Published var downloading = false
  @Published var progress = 0.0
  @Published var status = "未下载"
  var root: URL {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Product.group)
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  }
  var file: URL { root.appendingPathComponent("wanxiang-lts-zh-hans.gram") }
  var installed: Bool { FileManager.default.fileExists(atPath: file.path) }
  init() { if installed { status = "已下载 · 下次打开键盘启用" } }
  func download() async throws {
    guard !downloading else { return }
    downloading = true
    progress = 0
    status = "正在下载 0%"
    defer { downloading = false }
    let observer = DictionaryProgress { [weak self] progress in
      Task { @MainActor in
        self?.progress = progress
        self?.status = "正在下载 \(Int(progress * 100))%"
      }
    }
    do {
      let (temp, response) = try await URLSession.shared.download(
        from: URL(
          string:
            "https://vertick-1257312282.cos.ap-guangzhou.myqcloud.com/wanxiang-lts-zh-hans.gram")!,
        delegate: observer)
      defer { try? FileManager.default.removeItem(at: temp) }
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw ClientError.message("长句模型下载失败")
      }
      status = "正在校验模型…"
      let valid = try await Task.detached(priority: .utility) {
        let handle = try FileHandle(forReadingFrom: temp)
        defer { try? handle.close() }
        var hash = SHA256()
        var size = 0
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
          try Task.checkCancellation()
          size += data.count
          hash.update(data: data)
        }
        return size == 420_012_076
          && hash.finalize().map { String(format: "%02x", $0) }.joined()
            == "099b3e378bfe3d65201a82bfd10b0479602f2492f7328b1ebe97a8d781056340"
      }.value
      guard valid else { throw ClientError.message("模型完整性校验失败，请重试") }
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      if installed {
        _ = try FileManager.default.replaceItemAt(file, withItemAt: temp)
      } else {
        try FileManager.default.moveItem(at: temp, to: file)
      }
      status = "已下载 · 下次打开键盘启用"
      progress = 1
    } catch {
      status = "下载失败：\(error.localizedDescription)"
      throw error
    }
  }
  func remove() throws {
    if installed { try FileManager.default.removeItem(at: file) }
    status = "未下载"
    progress = 0
  }
}
