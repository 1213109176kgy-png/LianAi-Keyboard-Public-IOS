import AVFAudio
import Foundation

nonisolated protocol KeyboardClickPlayback: AnyObject {
  func prepare() -> Bool
  func play(volume: Float) -> Bool
}

nonisolated private final class FileKeyboardClickPlayback: KeyboardClickPlayback {
  private let player: AVAudioPlayer
  init?(url: URL) {
    guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
    self.player = player
  }
  func prepare() -> Bool {
    do { try AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers) }
    catch { return false }
    return player.prepareToPlay()
  }
  func play(volume: Float) -> Bool {
    player.volume = volume
    player.currentTime = 0
    return player.play()
  }
}

/// All playback state is confined to this queue. Audio services can block while
/// creating an output queue (or failing in the extension); they never run on the
/// keyboard's UI thread. Expired clicks are discarded instead of played later.
nonisolated final class KeyboardClickAudio: @unchecked Sendable {
  private let queue = DispatchQueue(label: "com.lianai.keyboard.click-audio", qos: .userInteractive)
  private let makePlayback: @Sendable () -> (any KeyboardClickPlayback)?
  private var playback: (any KeyboardClickPlayback)?
  private var attempted = false
  init(url: URL) { makePlayback = { FileKeyboardClickPlayback(url: url) } }
  init(makePlayback: @escaping @Sendable () -> (any KeyboardClickPlayback)?) {
    self.makePlayback = makePlayback
  }
  func prepare() { queue.async { [self] in prepareIfNeeded() } }
  func play(volume: Float) {
    guard volume > 0 else { return }
    let requested = ProcessInfo.processInfo.systemUptime
    queue.async { [self] in
      guard ProcessInfo.processInfo.systemUptime - requested < 0.08 else { return }
      prepareIfNeeded()
      guard ProcessInfo.processInfo.systemUptime - requested < 0.08 else { return }
      if playback?.play(volume: volume) == false {
        // Retry on the next keyboard appearance, not once per key after an
        // audio service failure. The user's saved volume stays unchanged.
        playback = nil
      }
    }
  }
  private func prepareIfNeeded() {
    guard !attempted else { return }
    attempted = true
    guard let candidate = makePlayback(), candidate.prepare() else { return }
    playback = candidate
  }
}
