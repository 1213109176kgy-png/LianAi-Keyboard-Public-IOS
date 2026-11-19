import UIKit

/// Matches Android's recommendation cards while retaining native accessibility.
@MainActor
final class AIResultOptionButton: UIButton {
  let textLabel = UILabel()
  init(text: String, fontSize: CGFloat, foreground: UIColor, fill: UIColor, stroke: UIColor,
       action: @escaping () -> Void) {
    super.init(frame: .zero)
    backgroundColor = fill
    layer.cornerRadius = 14
    layer.borderWidth = 1
    layer.borderColor = stroke.cgColor
    textLabel.text = text
    textLabel.textColor = foreground
    textLabel.font = .systemFont(ofSize: fontSize)
    textLabel.textAlignment = .left
    textLabel.numberOfLines = 1
    textLabel.lineBreakMode = .byTruncatingTail
    textLabel.adjustsFontSizeToFitWidth = false
    addSubview(textLabel)
    isAccessibilityElement = true
    accessibilityLabel = text
    accessibilityHint = "点击填入输入框；选择另一条可替换，不会发送"
    addAction(UIAction { _ in action() }, for: .touchUpInside)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func layoutSubviews() {
    super.layoutSubviews()
    textLabel.frame = bounds.insetBy(dx: 24, dy: 8)
  }
  override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.65 : 1 } }
}

@MainActor
final class AIResultPanel: UIView {
  let card = UIView()
  let closeButton: InputKey
  let optionButtons: [AIResultOptionButton]
  let newContentButton: InputKey?
  let retryButton: InputKey?
  let knowledgeButton: InputKey
  private let polish: Bool
  private let compact: Bool
  private let loading: Bool
  private let titleLabel = UILabel()
  private let emotionCard = UIView()
  private let emotionIcon = UILabel()
  private let emotionLabel = UILabel()
  private let caption = UILabel()
  private let loadingOrb = UIView()
  private let loadingGradient = CAGradientLayer()
  private let loadingIcon = UILabel()
  private let loadingLabel = UILabel()
  private let loadingHint = UILabel()

  init(polish: Bool, compact: Bool, dark: Bool, loading: Bool, emotion: String,
       options: [String], close: @escaping () -> Void, choose: @escaping (String) -> Void,
       retry: @escaping () -> Void, newContent: @escaping () -> Void,
       knowledgeTitle: String = "狗头军师知识库") {
    self.polish = polish; self.compact = compact; self.loading = loading
    func color(_ hex: UInt32) -> UIColor {
      UIColor(red: CGFloat((hex >> 16) & 255) / 255,
              green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    let accent = color(0xFF6B9D)
    let ink = color(dark ? 0xFFF9FA : 0x2D3436)
    let soft = color(dark ? 0x42343A : 0xFFF1F5)
    let option = color(dark ? 0x42343A : 0xFFFBFC)
    let stroke = color(dark ? 0x69525B : 0xFFDCE6)
    knowledgeButton = InputKey(knowledgeTitle + " ▾", background: .clear, foreground: accent, action: {})
    knowledgeButton.titleLabel?.font = .systemFont(ofSize: compact ? 10 : polish ? 11 : 12)
    knowledgeButton.accessibilityIdentifier = "aiKnowledge"
    closeButton = InputKey("×", background: polish ? .clear : soft, foreground: accent, action: close)
    closeButton.accessibilityIdentifier = "aiResultClose"
    closeButton.titleLabel?.font = .systemFont(ofSize: polish ? 23 : 22)
    closeButton.layer.cornerRadius = 18
    optionButtons = loading ? [] : options.prefix(3).enumerated().map { index, text in
      let button = AIResultOptionButton(text: text, fontSize: compact ? 12 : polish ? 14 : 13,
        foreground: ink, fill: option, stroke: stroke) { choose(text) }
      button.accessibilityIdentifier = "aiResult.\(index)"
      return button
    }
    if polish && !loading {
      let button = InputKey("写新内容", background: option, foreground: accent, action: newContent)
      button.layer.cornerRadius = 12
      button.titleLabel?.font = .systemFont(ofSize: compact ? 11 : 13)
      button.accessibilityIdentifier = "aiNewContent"
      newContentButton = button
    } else { newContentButton = nil }
    if !polish && !loading {
      let button = InputKey("重新分析", background: .clear, foreground: accent, action: retry)
      button.titleLabel?.font = .systemFont(ofSize: compact ? 11 : 12)
      button.accessibilityIdentifier = "aiReplyReanalyze"
      retryButton = button
    } else { retryButton = nil }
    super.init(frame: .zero)
    accessibilityIdentifier = "aiResultPanel"
    card.backgroundColor = color(dark ? 0x3A2E33 : 0xFFFFFF)
    card.layer.cornerRadius = 16
    addSubview(card)
    card.addSubview(knowledgeButton)
    if loading {
      loadingGradient.colors = [color(0xFF89B8).cgColor, color(0xFF977E).cgColor]
      loadingGradient.startPoint = CGPoint(x: 0, y: 0)
      loadingGradient.endPoint = CGPoint(x: 1, y: 1)
      loadingOrb.layer.addSublayer(loadingGradient)
      loadingOrb.clipsToBounds = true
      loadingIcon.text = "✨"; loadingIcon.font = .systemFont(ofSize: polish ? 34 : 32)
      loadingIcon.textAlignment = .center
      loadingLabel.text = polish ? "AI正在优化..." : "正在分析并生成3条回复..."
      loadingLabel.font = .systemFont(ofSize: compact ? 14 : polish ? 18 : 16, weight: .semibold)
      loadingLabel.textColor = accent; loadingLabel.textAlignment = .center
      loadingHint.text = "正在连接大模型，请稍候"
      loadingHint.font = .systemFont(ofSize: 13); loadingHint.textColor = color(0xFF977E)
      loadingHint.textAlignment = .center
      loadingLabel.accessibilityIdentifier = "aiResultLoading"
      [loadingOrb, loadingIcon, loadingLabel].forEach(card.addSubview)
      if polish { card.addSubview(loadingHint) }
      else { card.addSubview(closeButton) }
    } else {
      card.addSubview(closeButton)
      if polish {
        titleLabel.text = "AI优化话术"; titleLabel.font = .systemFont(ofSize: compact ? 12 : 13)
        titleLabel.textColor = accent; card.addSubview(titleLabel)
      } else {
        emotionCard.backgroundColor = soft; emotionCard.layer.cornerRadius = 14
        emotionIcon.text = "😊"; emotionIcon.font = .systemFont(ofSize: compact ? 20 : 24)
        emotionIcon.textAlignment = .center
        emotionLabel.text = emotion.isEmpty ? "积极期待" : emotion
        emotionLabel.font = .systemFont(ofSize: compact ? 12 : 14)
        emotionLabel.textColor = color(0xFF897E)
        emotionLabel.lineBreakMode = .byTruncatingTail
        emotionLabel.accessibilityIdentifier = "aiReplyEmotion"
        caption.text = "AI推荐回复（点击使用）"
        caption.font = .systemFont(ofSize: compact ? 11 : 12); caption.textColor = accent
        card.addSubview(emotionCard); emotionCard.addSubview(emotionIcon); emotionCard.addSubview(emotionLabel)
        card.addSubview(caption)
      }
      optionButtons.forEach(card.addSubview)
      if let newContentButton { card.addSubview(newContentButton) }
      if let retryButton { card.addSubview(retryButton) }
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func layoutSubviews() {
    super.layoutSubviews()
    let top: CGFloat = compact ? 4 : polish ? 6 : 8
    card.frame = CGRect(x: -1, y: top, width: bounds.width + 2, height: max(0, bounds.height - top - 5))
    let w = card.bounds.width, h = card.bounds.height
    let inset: CGFloat = compact ? 8 : 14
    if loading {
      let size: CGFloat = compact ? 62 : polish ? 110 : 100
      let orbTop: CGFloat = compact ? 28 : polish ? 58 : 65
      loadingOrb.frame = CGRect(x: (w-size)/2, y: orbTop, width: size, height: size)
      loadingOrb.layer.cornerRadius = size/2; loadingGradient.frame = loadingOrb.bounds
      loadingIcon.frame = loadingOrb.frame
      loadingLabel.frame = CGRect(x: 8, y: compact ? 112 : polish ? 194 : 191, width: w-16, height: 28)
      loadingHint.frame = CGRect(x: 8, y: compact ? 142 : 229, width: w-16, height: 22)
    } else if polish {
      titleLabel.frame = CGRect(x: inset, y: 8, width: max(0,w-170), height: 34)
      newContentButton?.frame = CGRect(x: w-144, y: 8, width: 94, height: 34)
    } else {
      emotionCard.frame = CGRect(x: inset, y: compact ? 8 : 14, width: max(0,w-inset-54), height: compact ? 34 : 52)
      emotionIcon.frame = CGRect(x: 0, y: 0, width: compact ? 40 : 60, height: emotionCard.bounds.height)
      let textLeft: CGFloat = compact ? 42 : 57
      emotionLabel.frame = CGRect(x: textLeft, y: 0, width: max(0,emotionCard.bounds.width-textLeft-8), height: emotionCard.bounds.height)
      caption.frame = CGRect(x: inset, y: compact ? 49 : 77, width: w-inset*2, height: 18)
    }
    closeButton.frame = CGRect(x: w-(polish ? 43 : 46), y: polish ? 8 : 10, width: polish ? 34 : 36, height: polish ? 34 : 36)
    let start: CGFloat = compact ? (polish ? 42 : 72) : polish ? 52 : 104
    let step: CGFloat = compact ? 38 : polish ? 76 : 75
    let rowHeight: CGFloat = compact ? 32 : polish ? 64 : 63
    for (index, button) in optionButtons.enumerated() {
      button.frame = CGRect(x: inset, y: start + CGFloat(index)*step, width: w-inset*2, height: rowHeight)
    }
    retryButton?.frame = CGRect(x: inset, y: max(0,h-(compact ? 32 : 45)), width: w/2-inset-8, height: compact ? 24 : 37)
    let footerHeight: CGFloat = compact ? 24 : 37
    let footerTop = max(0, h - (compact ? 32 : 45))
    knowledgeButton.frame = CGRect(x: polish || loading ? inset : w/2+8, y: footerTop,
      width: polish || loading ? w-2*inset : w/2-inset-8, height: footerHeight)
  }
}
