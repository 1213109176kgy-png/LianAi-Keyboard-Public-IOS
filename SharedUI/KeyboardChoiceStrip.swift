import UIKit

/// A drag must cancel the button even when touch delivery starts immediately.
@MainActor
final class KeyboardStripScrollView: UIScrollView {
  override func touchesShouldCancel(in view: UIView) -> Bool { true }
}

/// Reuses the same controls/constraints as composition changes. Choices still
/// activate on release so a horizontal swipe never commits a candidate.
@MainActor
final class KeyboardChoiceStrip: UIView {
  let scroll = KeyboardStripScrollView()
  private let line = UIStackView()
  private var buttons: [InputKey] = []
  private var widths: [NSLayoutConstraint] = []
  private var titles: [String] = []
  init(spacing: CGFloat) {
    super.init(frame: .zero)
    line.spacing = spacing
    scroll.delaysContentTouches = false
    scroll.showsHorizontalScrollIndicator = false
    if #available(iOS 26.0, *) {
      scroll.topEdgeEffect.isHidden = true
      scroll.bottomEdgeEffect.isHidden = true
      scroll.leftEdgeEffect.isHidden = true
      scroll.rightEdgeEffect.isHidden = true
    }
    scroll.translatesAutoresizingMaskIntoConstraints = false
    line.translatesAutoresizingMaskIntoConstraints = false
    addSubview(scroll)
    scroll.addSubview(line)
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
      scroll.topAnchor.constraint(equalTo: topAnchor),
      scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
      line.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      line.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      line.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      line.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      line.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
    ])
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func update(_ titles: [String], make: (String) -> InputKey,
              configure: (InputKey, Int) -> CGFloat) {
    for index in titles.indices {
      if index == buttons.count {
        let button = make(titles[index])
        let width = button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
        width.isActive = true
        buttons.append(button); widths.append(width)
        line.addArrangedSubview(button)
      }
      let button = buttons[index]
      if button.isHidden { button.isHidden = false; widths[index].isActive = true }
      if button.title(for: .normal) != titles[index] { button.setTitle(titles[index], for: .normal) }
      button.accessibilityLabel = titles[index]
      let width = configure(button, index)
      if widths[index].constant != width { widths[index].constant = width }
    }
    for index in titles.count..<buttons.count where !buttons[index].isHidden {
      widths[index].isActive = false
      buttons[index].isHidden = true
      buttons[index].pressed = nil
    }
    if self.titles != titles {
      self.titles = titles
      if scroll.contentOffset != .zero { scroll.setContentOffset(.zero, animated: false) }
    }
  }
}
