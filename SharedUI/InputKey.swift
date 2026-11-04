import UIKit

@MainActor
final class InputKey: UIButton {
  var pressed: (() -> Void)?
  var holdAction: (() -> Void)? { didSet { updateHoldRecognizer() } }
  /// Text keys commit on contact; space, return and scrollable choices wait for release.
  var activatesOnTouchDown = false
  private var holdRecognizer: UILongPressGestureRecognizer?
  var holdEnded: ((Bool) -> Void)?
  var holdMoved: ((Bool) -> Void)?
  var textPadding = UIEdgeInsets.zero
  private var gradient: CAGradientLayer?
  private var repeated = false
  private var holding = false
  private var repeatTask: Task<Void, Never>?
  init(_ title: String, background: UIColor, foreground: UIColor, action: @escaping () -> Void) {
    super.init(frame: .zero)
    pressed = action
    setTitle(title, for: .normal)
    setTitleColor(foreground, for: .normal)
    backgroundColor = background
    layer.cornerRadius = 9
    titleLabel?.font = .systemFont(ofSize: 18)
    titleLabel?.adjustsFontSizeToFitWidth = true
    titleLabel?.minimumScaleFactor = 0.6
    addAction(
      UIAction { [weak self] _ in
        guard let self else { return }
        if !repeated && !activatesOnTouchDown { pressed?() }
        repeated = false
      }, for: .touchUpInside)
    accessibilityLabel = title
    addAction(UIAction { [weak self] _ in
      guard let self else { return }
      repeated = false
      if activatesOnTouchDown { pressed?() }
    }, for: .touchDown)
  }
  private func updateHoldRecognizer() {
    guard holdAction != nil else {
      if let holdRecognizer { removeGestureRecognizer(holdRecognizer) }
      holdRecognizer = nil
      return
    }
    guard holdRecognizer == nil else { return }
    let hold = UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:)))
    hold.minimumPressDuration = 0.42
    addGestureRecognizer(hold)
    holdRecognizer = hold
  }
  override func accessibilityActivate() -> Bool {
    pressed?()
    return true
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func applyGradient(_ colors: [UIColor]) {
    let gradient = CAGradientLayer()
    gradient.colors = colors.map(\.cgColor)
    gradient.startPoint = CGPoint(x: 0, y: 0.5)
    gradient.endPoint = CGPoint(x: 1, y: 0.5)
    layer.insertSublayer(gradient, at: 0)
    layer.masksToBounds = true
    backgroundColor = .clear
    self.gradient = gradient
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    gradient?.frame = bounds
    if textPadding != .zero { titleLabel?.frame = bounds.inset(by: textPadding) }
  }
  override var isHighlighted: Bool { didSet { alpha = isHighlighted || holding ? 0.6 : 1 } }
  @objc private func longPress(_ gesture: UILongPressGestureRecognizer) {
    switch gesture.state {
    case .began:
      holding = true
      alpha = 0.6
      repeated = true
      holdAction?()
    case .changed:
      holdMoved?(gesture.location(in: self).y < -45)
    case .ended, .cancelled, .failed:
      holding = false
      alpha = isHighlighted ? 0.6 : 1
      holdEnded?(gesture.state != .ended || gesture.location(in: self).y < -45)
      repeatTask?.cancel()
      repeatTask = nil
    default: break
    }
  }
  func enableDeleteRepeat() {
    holdAction = { [weak self] in
      self?.repeatTask = Task { @MainActor [weak self] in
        while !Task.isCancelled && self != nil {
          self?.pressed?()
          try? await Task.sleep(for: .milliseconds(80))
        }
      }
    }
  }
}
