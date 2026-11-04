import AVFAudio
import AudioToolbox
import ImageIO
import LianAiCore
import PhotosUI
import UIKit

@MainActor
final class KeyboardViewController: UIInputViewController, PHPickerViewControllerDelegate {
  private let store = SharedStore.shared
  private let rime = RimeRuntime()
  private var api: APIClient { KeyboardUITestSupport.client() }
  private let rootStack = UIStackView()
  private var renderTarget: UIStackView?
  private var stack: UIStackView { renderTarget ?? rootStack }
  private var typingPrefix: UIStackView?
  private var typingKeys: UIStackView?
  private var typingSignature: String?
  private var prefixSignature: String?
  private var candidateStrip: KeyboardChoiceStrip?
  private var spellingStrip: KeyboardChoiceStrip?
  private weak var draftEditor: UILabel?
  private var letterKeys: [(InputKey, String)] = []
  private let keyboardBody = UIView()
  private var keyboardBodyTop: NSLayoutConstraint?
  private var voiceBodyHeight: NSLayoutConstraint?
  private var voiceOriginalHeight: CGFloat?
  private var preparingVoice = false
  private var voicePreparedComposition = false
  private var height: NSLayoutConstraint?
  private var renderingHeight: CGFloat = 0
  private var mode = "键盘"
  private var english = false
  private var numberPad = false
  private var symbolPage: Int?
  private var emoji = false
  private var emojiCategory = 0
  private var emojiPage = 0
  private var kaomoji = false
  private var punctuation = false
  private var punctuationInserted = false
  private var punctuationTime = Date.distantPast
  private var punctuationContext: String?
  private var expanded = false
  private var shift = false
  private var capsLock = false
  private var lastShift = Date.distantPast
  private var lastSpace = Date.distantPast
  private var draft = ""
  private var editingLocalText: Bool { mode == "超会说" }
  private var draftCursor = 0
  private var relation = "通用"
  private var options: [String] = []
  private var loading = false
  private var emotion = ""
  private var lastSource = ""
  private var lastImage: Data?
  private var error = ""
  private var aiGuide = false
  private struct InlinePrompt {
    let title: String
    let message: String
    let confirmTitle: String?
    let confirm: (() -> Void)?
    let dismissTitle: String
  }
  private var inlinePrompt: InlinePrompt?
  private var voiceRequest: UUID?
  private var voiceSession: UUID?
  private var voiceAnchor: VoiceInsertionAnchor?
  private var voicePoll: Task<Void, Never>?
  private var voiceBanner: UIView?
  private var voiceStatusLabel: UILabel?
  private var voiceTranscriptLabel: UILabel?
  private var voiceBegan = Date()
  private var voiceHeartbeat = Date.distantPast
  private var voiceFinishing = false
  private var voiceCancelOnRelease = false
  private var screenshotPicker: PHPickerViewController?
  private var screenshotOverlay: UIView?
  private var inputActive = false
  private var currentDocument: UUID? {
    guard inputActive else { return nil }
    return (textDocumentProxy as? NSObject).flatMap { KeyboardDocumentContext.identifier(of: $0) }
  }
  private var work: Task<Void, Never>?
  private var generation = UUID()
  private var document: UUID?
  private var tracker = InsertTracker()
  private var englishBuffer = ""
  private var selectedSpelling = ""
  private var spellingPrefix = ""
  private var predictions: [String] = []
  private var predictionTokens: [String] = []
  private var predictionLearning: [PredictionLearning] = []
  private var clickAudio: KeyboardClickAudio?
  private var impactFeedback: UIImpactFeedbackGenerator?
  private var impactStyle: UIImpactFeedbackGenerator.FeedbackStyle?
  private let selectionFeedback = UISelectionFeedbackGenerator()
  private var settings: Settings { store.settings }
  private var learningDefaults: UserDefaults {
    hasFullAccess ? UserDefaults(suiteName: Product.group) ?? .standard : .standard
  }
  private var compact: Bool { traitCollection.verticalSizeClass == .compact }
  private var primaryRowHeight: CGFloat {
    compact ? 28 : english || settings.layout == "九宫格拼音" ? 52 : 44
  }
  private var dark: Bool {
    settings.theme == "暗黑模式"
      || settings.theme == "自适应系统" && traitCollection.userInterfaceStyle == .dark
  }
  private var bg: UIColor { color(dark ? 0x30262B : 0xFFF9FA) }
  private var panel: UIColor { color(dark ? 0x4E3E45 : 0xFFFFFF) }
  private var cardColor: UIColor { color(dark ? 0x3A2E33 : 0xFFFFFF) }
  private var tabColor: UIColor { dark ? color(0x3A2E33) : UIColor.white.withAlphaComponent(190.0/255) }
  private var keyColor: UIColor { color(dark ? 0x5B4850 : 0xE5DDE1) }
  private var ink: UIColor { color(dark ? 0xFFF9FA : 0x2D3436) }
  private var muted: UIColor { color(dark ? 0xDAC4CC : 0x999999) }
  private var accent: UIColor { color(0xFF6B9D) }
  override func viewDidLoad() {
    super.viewDidLoad()
    stack.accessibilityIdentifier = "keyboardContent"
    stack.axis = .vertical
    stack.spacing = 7
    stack.translatesAutoresizingMaskIntoConstraints = false
    keyboardBody.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(keyboardBody)
    keyboardBody.addSubview(stack)
    keyboardBodyTop = keyboardBody.topAnchor.constraint(equalTo: view.topAnchor)
    NSLayoutConstraint.activate([
      keyboardBody.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      keyboardBody.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      keyboardBody.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      keyboardBodyTop!,
      stack.leadingAnchor.constraint(equalTo: keyboardBody.leadingAnchor, constant: 6),
      stack.trailingAnchor.constraint(equalTo: keyboardBody.trailingAnchor, constant: -6),
      stack.topAnchor.constraint(equalTo: keyboardBody.topAnchor, constant: 5),
      stack.bottomAnchor.constraint(equalTo: keyboardBody.safeAreaLayoutGuide.bottomAnchor, constant: -5),
    ])
    height = view.heightAnchor.constraint(equalToConstant: 380)
    height?.priority = .init(999)
    height?.isActive = true
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    inputActive = false
    document = nil
    typingSignature = nil
    closeScreenshotPicker()
    cancelVoice()
    store.reload()
    let defaults = UserDefaults(suiteName: Product.group)
    if let stamp = defaults?.string(forKey: "clearPredictionLearning"),
      UserDefaults.standard.string(forKey: "appliedPredictionClear") != stamp
    {
      UserDefaults.standard.removeObject(forKey: "predictionPairs")
      UserDefaults.standard.set(stamp, forKey: "appliedPredictionClear")
      predictions = []
      predictionTokens = []
      predictionLearning = []
      learningDefaults.removeObject(forKey: "predictionLearningV2")
    }
    if let stamp = defaults?.string(forKey: "clearRimeLearning"),
      UserDefaults.standard.string(forKey: "appliedEnglishClear") != stamp
    {
      UserDefaults.standard.removeObject(forKey: "englishLearning")
      UserDefaults.standard.set(stamp, forKey: "appliedEnglishClear")
    }
    predictionTokens = []
    predictionLearning = (learningDefaults.data(forKey: "predictionLearningV2").flatMap {
      try? JSONDecoder().decode([PredictionLearning].self, from: $0)
    }) ?? []
    rime.start(nineKey: settings.layout == "九宫格拼音")
    clickAudio = nil
    prepareFeedback()
    mode =
      settings.startup == "默认（上次使用的模式）"
      ? UserDefaults.standard.string(forKey: "lastMode") ?? "键盘"
      : settings.startup == "超会说" || settings.startup == "帮你回" ? settings.startup : "键盘"
    english = settings.startup == "默认（上次使用的模式）" ? UserDefaults.standard.bool(forKey: "lastEnglish") : settings.startup == "英文"
    numberPad = false
    symbolPage = nil
    emoji = false
    punctuation = false
    expanded = false
    error = rime.error
    render()
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // During viewWillAppear UIKit may still expose the previous host's proxy.
    // Bind its document only from an input callback or a user action after the
    // view is attached, never while UIKit is reconnecting the remote host.
    inputActive = true
  }
  override func viewWillDisappear(_ animated: Bool) {
    inputActive = false
    document = nil
    cancelVoice()
    cancelWork()
    tracker.invalidate()
    super.viewWillDisappear(animated)
  }
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    UserDefaults.standard.set(english, forKey: "lastEnglish")
    closeScreenshotPicker()
    cancelVoice()
    cancelWork()
    rime.close()
    tracker.invalidate()
  }
  override func viewWillTransition(
    to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator
  ) {
    super.viewWillTransition(to: size, with: coordinator)
    cancelVoice()
    coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.render() }
  }
  override func textDidChange(_ textInput: (any UITextInput)?) {
    super.textDidChange(textInput)
    guard inputActive else { return }
    updateDocument()
  }
  private func updateDocument() {
    let identifier = currentDocument
    if document != identifier || identifier == nil {
      document = identifier
      cancelVoice()
      inlinePrompt = nil
      tracker.invalidate()
      rime.clear()
      englishBuffer = ""
      predictions = []
      predictionTokens = []
      cancelWork()
      options = []
    }
  }
  override func selectionDidChange(_ textInput: (any UITextInput)?) {
    super.selectionDidChange(textInput)
    guard inputActive else { return }
    if voiceRequest != nil && voiceAnchor != voiceInsertionAnchor() { cancelVoice() }
    tracker.invalidate()
  }
  private func color(_ rgb: UInt32) -> UIColor {
    UIColor(
      red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
      blue: CGFloat(rgb & 255) / 255, alpha: 1)
  }
  private func cancelWork() {
    work?.cancel()
    work = nil
    generation = UUID()
    loading = false
  }
  private func key(
    _ title: String, special: Bool = false, primary: Bool = false, immediate: Bool = false, action: @escaping () -> Void
  ) -> InputKey {
    let button = InputKey(
      title, background: primary ? accent : special ? keyColor : panel,
      foreground: primary ? .white : ink
    ) { [weak self] in
      self?.updateDocument()
      self?.feedback()
      action()
    }
    button.activatesOnTouchDown = immediate
    let icons = ["⌫": "delete", "🌐": "globe", "🎙": "mic", "☺": "smile", "⌄": "chevron_down"]
    if let icon = icons[title], let image = UIImage(named: "lucide_" + icon) {
      button.setTitle(nil, for: .normal)
      button.setImage(image.withRenderingMode(.alwaysTemplate), for: .normal)
      button.tintColor = primary ? .white : ink
    }
    return button
  }
  private func prepareFeedback() {
    let style: UIImpactFeedbackGenerator.FeedbackStyle?
    switch settings.haptics {
    case "弱": style = .light
    case "适中": style = .medium
    case "较强", "强": style = .heavy
    default: style = nil
    }
    if impactStyle != style {
      impactStyle = style
      impactFeedback = style.map { UIImpactFeedbackGenerator(style: $0) }
    }
    if settings.haptics == "系统" { selectionFeedback.prepare() }
    else { impactFeedback?.prepare() }
    if settings.volume > 0, hasFullAccess, clickAudio == nil,
      let url = Bundle.main.url(forResource: "keyboard-click", withExtension: "wav") {
      clickAudio = KeyboardClickAudio(url: url)
      clickAudio?.prepare()
    }
  }
  private func feedback() {
    switch settings.haptics {
    case "系统": selectionFeedback.selectionChanged()
    case "弱": impactFeedback?.impactOccurred(intensity: 0.35)
    case "适中": impactFeedback?.impactOccurred(intensity: 0.55)
    case "较强": impactFeedback?.impactOccurred(intensity: 0.75)
    case "强": impactFeedback?.impactOccurred(intensity: 1)
    default: break
    }
    clickAudio?.play(volume: Float(settings.volume))
  }
  private func row(_ views: [UIView], height: CGFloat? = nil, equal: Bool = true, widthRatio: CGFloat = 1) {
    let row = UIStackView(arrangedSubviews: views)
    row.axis = .horizontal
    row.spacing = 6
    row.distribution = equal ? .fillEqually : .fill
    row.heightAnchor.constraint(
      equalToConstant: compact ? min(height ?? primaryRowHeight, 30) : height ?? primaryRowHeight
    ).isActive = true
    if widthRatio < 1 {
      let wrapper = UIView()
      row.translatesAutoresizingMaskIntoConstraints = false
      wrapper.addSubview(row)
      NSLayoutConstraint.activate([
        row.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
        row.topAnchor.constraint(equalTo: wrapper.topAnchor),
        row.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        row.widthAnchor.constraint(equalTo: wrapper.widthAnchor, multiplier: widthRatio),
      ])
      stack.addArrangedSubview(wrapper)
    } else { stack.addArrangedSubview(row) }
  }
  private func grid(_ cells: [(UIView, Int, Int, Int, Int)], rows: Int = 4, columns: Int = 5) {
    let grid = UIView()
    let unit = UILayoutGuide()
    grid.addLayoutGuide(unit)
    let gap: CGFloat = 6
    let h = primaryRowHeight
    NSLayoutConstraint.activate([
      unit.widthAnchor.constraint(
        equalTo: grid.widthAnchor, multiplier: 1 / CGFloat(columns),
        constant: -gap * CGFloat(columns - 1) / CGFloat(columns)),
      grid.heightAnchor.constraint(equalToConstant: h * CGFloat(rows) + gap * CGFloat(rows - 1)),
    ])
    for (cell, column, row, columnSpan, rowSpan) in cells {
      grid.addSubview(cell)
      cell.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        cell.topAnchor.constraint(equalTo: grid.topAnchor, constant: CGFloat(row) * (h + gap)),
        cell.widthAnchor.constraint(
          equalTo: unit.widthAnchor, multiplier: CGFloat(columnSpan),
          constant: gap * CGFloat(columnSpan - 1)),
        cell.heightAnchor.constraint(
          equalToConstant: h * CGFloat(rowSpan) + gap * CGFloat(rowSpan - 1)),
      ])
      // Multipliers cannot be used on positional anchors; a guide locates each column.
      let offset = UILayoutGuide()
      grid.addLayoutGuide(offset)
      offset.leadingAnchor.constraint(equalTo: grid.leadingAnchor).isActive = true
      offset.widthAnchor.constraint(
        equalTo: unit.widthAnchor, multiplier: CGFloat(column), constant: gap * CGFloat(column)
      ).isActive = true
      cell.leadingAnchor.constraint(equalTo: offset.trailingAnchor).isActive = true
    }
    stack.addArrangedSubview(grid)
  }
  private func label(_ text: String, size: CGFloat = 13, color: UIColor? = nil, bold: Bool = false)
    -> UILabel
  {
    let l = UILabel()
    l.text = text
    l.textColor = color ?? ink
    l.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
    l.numberOfLines = 0
    return l
  }
  private func render() {
    guard isViewLoaded, !preparingVoice else { return }
    if voiceBanner != nil {
      if voiceRequest == nil { clearVoiceSetupRequest() }
      cancelVoice()
    }
    defer {
      if height?.constant != renderingHeight { height?.constant = renderingHeight }
    }
    view.backgroundColor = bg
    if ["键盘", "超会说"].contains(mode), inlinePrompt == nil, !aiGuide,
      !loading, options.isEmpty, !expanded, !emoji, symbolPage == nil,
      !numberPad, !punctuation, !kaomoji {
      renderTyping()
      return
    }
    typingSignature = nil
    typingPrefix = nil
    typingKeys = nil
    letterKeys.removeAll()
    resetTypingPrefix()
    stack.arrangedSubviews.forEach {
      stack.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    renderingHeight = compact ? (["帮你回", "超会说"].contains(mode) ? 290 : 210)
      : mode == "帮你回" ? 447 : mode == "超会说" ? 527 : 335
    stack.spacing = compact ? 4 : 7
    if mode == "键盘" && (!rime.preedit.isEmpty || !englishBuffer.isEmpty) {
      candidatesBar()
    } else if settings.predictions && !predictions.isEmpty && mode == "键盘" {
      predictionBar()
    } else {
      header()
    }
    if let prompt = inlinePrompt {
      promptPanel(prompt)
    } else if aiGuide && ["帮你回", "超会说"].contains(mode) {
      guidePanel()
    } else if mode == "帮你回" {
      replyPanel()
    } else if mode == "超会说" && (loading || !options.isEmpty) {
      resultPanel(polish: true)
    } else if mode == "剪贴板" {
      clipboardPanel()
    } else {
      if editingLocalText { draftPanel() }
      if expanded && !rime.preedit.isEmpty {
        expandedCandidates()
      } else if emoji {
        emojiKeyboard()
      } else if let symbolPage {
        symbolsKeyboard(page: symbolPage)
      } else if numberPad {
        numberKeyboard()
      } else if english || settings.layout != "九宫格拼音" {
        qwerty()
      } else {
        nineKey()
      }
    }
  }
  /// Candidate/draft strips change while typing; the actual key grid stays
  /// attached so rapid taps don't destroy their own controls and constraints.
  private func renderTyping() {
    if english { InputLexicon.prepareEnglishCompletions() }
    let signature = "\(mode)|\(english)|\(settings.layout)|\(compact)|\(dark)"
    let rebuild = typingSignature != signature || typingPrefix == nil || typingKeys == nil
    rootStack.spacing = compact ? 4 : 7
    renderingHeight = compact ? (editingLocalText ? 290 : 210) : mode == "超会说" ? 527 : 335
    if rebuild {
      letterKeys.removeAll()
      rootStack.arrangedSubviews.forEach { rootStack.removeArrangedSubview($0); $0.removeFromSuperview() }
      let prefix = UIStackView(); prefix.axis = .vertical; prefix.spacing = rootStack.spacing
      let keys = UIStackView(); keys.axis = .vertical; keys.spacing = rootStack.spacing
      keys.accessibilityIdentifier = "keyboardTypingKeys"
      typingPrefix = prefix; typingKeys = keys; typingSignature = signature
      rootStack.addArrangedSubview(prefix); rootStack.addArrangedSubview(keys)
    }
    guard let prefix = typingPrefix, let keys = typingKeys else { return }
    if !rebuild && english {
      let uppercase = shouldUppercase()
      for (button, letter) in letterKeys {
        let title = uppercase ? letter.uppercased() : letter
        if button.title(for: .normal) != title { button.setTitle(title, for: .normal) }
        button.accessibilityLabel = title
      }
    }
    let composing = !rime.preedit.isEmpty || !englishBuffer.isEmpty
    let top = mode == "键盘" && composing ? "candidates"
      : settings.predictions && !predictions.isEmpty && mode == "键盘" ? "predictions" : "header"
    let spelling = !english && settings.layout == "九宫格拼音" && !rime.preedit.isEmpty
    let nextPrefix = "\(top)|\(composing)|\(spelling)|\(relation)|\(top == "predictions" ? predictions.joined(separator: "|") : "")"
    renderTarget = prefix
    if rebuild || prefixSignature != nextPrefix {
      resetTypingPrefix()
      prefix.arrangedSubviews.forEach { prefix.removeArrangedSubview($0); $0.removeFromSuperview() }
      prefixSignature = nextPrefix
      if top == "candidates" { candidatesBar() }
      else if top == "predictions" { predictionBar() }
      else { header() }
      if editingLocalText { draftPanel() }
      if spelling { spellingBar() }
    } else {
      if composing { updateCandidateStrip() }
      if spelling { updateSpellingStrip() }
      if editingLocalText { updateDraftEditor() }
    }
    if editingLocalText && composing { renderingHeight += compact ? 34 : 49 }
    if spelling { renderingHeight += 35 }
    renderTarget = keys
    if rebuild {
      if english || settings.layout != "九宫格拼音" { qwerty() }
      else { nineKey(includeSpelling: false) }
    } else {
      renderingHeight -= compact ? 28 : 51
    }
    renderTarget = nil
  }
  private func header() {
    var tabs = settings.keyboardModes
    if !tabs.contains(mode) && mode != "键盘" { tabs = ["键盘", "帮你回", "超会说"] }
    let buttons = tabs.map { name in
      let b = key(name) { [weak self] in self?.setMode(name) }
      b.titleLabel?.font = .systemFont(ofSize: 14, weight: name == mode ? .semibold : .regular)
      b.accessibilityIdentifier = "keyboardMode." + name
      b.setTitleColor(name == mode ? .white : muted, for: .normal)
      b.backgroundColor = .clear
      b.layer.cornerRadius = 14
      b.heightAnchor.constraint(equalToConstant: compact ? 24 : 32).isActive = true
      if name == mode { b.applyGradient([accent, color(0xFFA07A)]) }
      return b
    }
    let tabsRow = UIStackView(arrangedSubviews: buttons)
    tabsRow.distribution = .fillEqually
    tabsRow.alignment = .center
    tabsRow.isLayoutMarginsRelativeArrangement = true
    tabsRow.layoutMargins = UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
    tabsRow.backgroundColor = tabColor
    tabsRow.layer.cornerRadius = 20
    var controls: [UIView] = [tabsRow]
    if settings.recentPaste && mode == "键盘" && hasFullAccess && UIPasteboard.general.hasStrings {
      let paste = key("粘贴") { [weak self] in self?.pasteText() }
      paste.titleLabel?.font = .systemFont(ofSize: 12)
      paste.widthAnchor.constraint(equalToConstant: 42).isActive = true
      controls.append(paste)
    }
    let close = key("⌄") { [weak self] in self?.dismissKeyboard() }
    close.backgroundColor = tabColor
    close.tintColor = muted
    close.layer.cornerRadius = 19
    close.widthAnchor.constraint(equalToConstant: 38).isActive = true
    controls.append(close)
    row(controls, height: compact ? 30 : 38, equal: false)
  }
  private func setMode(_ name: String) {
    cancelVoice()
    flush()
    cancelWork()
    options = []
    error = ""
    aiGuide = false
    inlinePrompt = nil
    mode = name
    draftCursor = draft.count
    UserDefaults.standard.set(name, forKey: "lastMode")
    render()
  }
  private func candidateChoices() -> [InputCandidate] {
    var result = rime.candidates
    let words = settings.professional + settings.typing
    let raw = rime.raw
    if !raw.isEmpty {
      let custom = words.filter { word in
        let code =
          word.hint.isEmpty
          ? (word.term.applyingTransform(.mandarinToLatin, reverse: false)?.applyingTransform(
            .stripDiacritics, reverse: false) ?? "") : word.hint
        let compact = code.lowercased().filter { $0.isASCII && $0.isLetter }
        return (settings.layout == "九宫格拼音" ? Self.t9(compact) : compact).hasPrefix(raw)
      }.prefix(8).map { InputCandidate(text: $0.term, comment: $0.hint, index: -1) }
      result = Array(custom) + result
    }
    guard !selectedSpelling.isEmpty else { return result }
    let filtered = result.filter {
      InputLexicon.reading($0.text, digits: raw).split(separator: " ").first?.hasPrefix(
        selectedSpelling) == true
    }
    return filtered.isEmpty ? result : filtered
  }
  private func resetTypingPrefix() {
    prefixSignature = nil
    candidateStrip = nil
    spellingStrip = nil
    draftEditor = nil
  }
  private func choiceAction(_ action: @escaping () -> Void) -> () -> Void {
    { [weak self] in
      self?.updateDocument()
      self?.feedback()
      action()
    }
  }
  private func candidatesBar() {
    let strip = KeyboardChoiceStrip(spacing: englishBuffer.isEmpty ? 8 : 10)
    candidateStrip = strip
    strip.scroll.accessibilityIdentifier = "keyboardCandidateScroll"
    updateCandidateStrip()
    if !englishBuffer.isEmpty { row([strip], height: 42); return }
    let expand = key(expanded ? "⌄" : "›", special: true) { [weak self] in
      self?.expanded.toggle()
      self?.rime.more()
      self?.render()
    }
    expand.widthAnchor.constraint(equalToConstant: 38).isActive = true
    row([strip, expand], height: 42, equal: false)
  }
  private func updateCandidateStrip() {
    guard let candidateStrip else { return }
    if !englishBuffer.isEmpty {
      let choices = InputLexicon.completions(
        englishBuffer, custom: settings.typing.map(\.term),
        learned: learningDefaults.dictionary(forKey: "englishLearning") as? [String: Int] ?? [:])
      candidateStrip.update(choices, make: { key($0) {} }) { button, index in
        let word = choices[index]
        button.pressed = choiceAction { [weak self] in
          self?.englishBuffer = ""
          self?.recordEnglish(word)
          self?.insert(word)
          self?.textDocumentProxy.unmarkText()
          self?.render()
        }
        return 44
      }
    } else {
      let choices = Array(candidateChoices().prefix(30))
      candidateStrip.update(choices.map(\.text), make: { key($0) {} }) { button, index in
        let candidate = choices[index]
        button.titleLabel?.font = .systemFont(ofSize: CGFloat(settings.candidateSize))
        button.pressed = choiceAction { [weak self] in self?.choose(candidate) }
        return CGFloat(max(44, candidate.text.count * settings.candidateSize + 14))
      }
    }
  }
  private func predictionBar() {
    let scroll = KeyboardStripScrollView()
    let line = UIStackView()
    line.spacing = 8
    for text in predictions {
      line.addArrangedSubview(
        key(text) { [weak self] in
          self?.insert(text + (PredictionEngine.appendSpace(text) ? " " : ""))
          self?.render()
        })
    }
    attachHorizontal(line, to: scroll)
    let close = key("×", special: true) { [weak self] in
      self?.predictions = []
      self?.render()
    }
    close.widthAnchor.constraint(equalToConstant: 38).isActive = true
    row([scroll, close], height: 42, equal: false)
  }
  private func spellingBar() {
    let strip = KeyboardChoiceStrip(spacing: 6)
    spellingStrip = strip
    updateSpellingStrip()
    row([strip], height: 28)
  }
  private func updateSpellingStrip() {
    guard let spellingStrip else { return }
    let raw = rime.raw
    if !raw.hasPrefix(spellingPrefix) { selectedSpelling = "" }
    let all = rime.candidates.map {
      InputLexicon.reading($0.text, digits: raw).components(separatedBy: " ")[0]
    }
    var seen = Set<String>()
    let syllables = all.filter {
      !$0.isEmpty && (raw.hasPrefix(InputLexicon.code($0)) || InputLexicon.code($0).hasPrefix(raw))
        && seen.insert($0).inserted
    }
    let choices =
      ["全部"] + syllables
      + syllables.map { String($0.prefix(1)) }.filter { seen.insert($0).inserted }
    spellingStrip.update(choices, make: { key($0, special: true) {} }) { button, index in
      let spelling = choices[index]
      let selected = spelling == selectedSpelling
      button.backgroundColor = selected ? accent : keyColor
      button.setTitleColor(selected ? .white : ink, for: .normal)
      button.titleLabel?.font = .systemFont(ofSize: 13)
      button.pressed = choiceAction { [weak self] in
        self?.selectedSpelling = spelling == "全部" ? "" : spelling
        self?.spellingPrefix = InputLexicon.code(spelling)
        self?.render()
      }
      return 44
    }
  }
  private func attachHorizontal(_ line: UIStackView, to scroll: UIScrollView, vertical: Bool = false) {
    if #available(iOS 26.0, *) {
      // A keyboard strip is only one line tall. UIKit's automatic scroll-edge
      // blur can cover the entire text instead of just a decorative boundary.
      scroll.topEdgeEffect.isHidden = true
      scroll.bottomEdgeEffect.isHidden = true
      scroll.leftEdgeEffect.isHidden = true
      scroll.rightEdgeEffect.isHidden = true
    }
    line.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(line)
    NSLayoutConstraint.activate([
      line.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      line.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      line.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      line.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      vertical ? line.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        : line.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
    ])
    scroll.delaysContentTouches = false
    scroll.showsHorizontalScrollIndicator = false
  }
  private func choose(_ candidate: InputCandidate) {
    selectedSpelling = ""
    spellingPrefix = ""
    if candidate.index < 0 {
      rime.clear()
      if !editingLocalText {
        textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
        textDocumentProxy.unmarkText()
      }
      insert(candidate.text)
    } else {
      apply(rime.choose(candidate.index))
    }
    expanded = false
    render()
  }
  private func apply(_ committed: String?) {
    if let committed { insert(committed) }
    if !editingLocalText {
      if !rime.preedit.isEmpty {
        textDocumentProxy.setMarkedText(
          rime.displayPreedit,
          selectedRange: NSRange(location: rime.displayPreedit.utf16.count, length: 0))
      } else {
        textDocumentProxy.unmarkText()
      }
    }
  }
  private func insert(_ text: String) {
    if editingLocalText {
      let i = draft.index(draft.startIndex, offsetBy: min(draftCursor, draft.count))
      draft.insert(contentsOf: text, at: i)
      draftCursor += text.count
    } else {
      textDocumentProxy.insertText(text)
      learn(text)
    }
    tracker.invalidate()
  }
  private func flush() {
    if !englishBuffer.isEmpty {
      let text = InputLexicon.completions(
        englishBuffer, custom: settings.typing.map(\.term),
        learned: learningDefaults.dictionary(forKey: "englishLearning") as? [String: Int] ?? [:]
      ).first ?? englishBuffer
      englishBuffer = ""
      insert(text)
      recordEnglish(text)
    }
    if !rime.preedit.isEmpty {
      if let c = candidateChoices().first {
        choose(c)
      } else {
        let raw = rime.raw
        rime.clear()
        insert(raw)
      }
    }
  }
  private func type(_ text: String) {
    error = ""
    punctuationInserted = false
    predictions = []
    if english {
      let letter = shouldUppercase() ? text.uppercased() : text
      englishBuffer += letter
      if !editingLocalText {
        textDocumentProxy.setMarkedText(
          englishBuffer, selectedRange: NSRange(location: englishBuffer.utf16.count, length: 0))
      }
      if shift && !capsLock { shift = false }
      render()
      return
    }
    if rime.ready {
      apply(rime.key(text))
      if settings.layout == "九宫格拼音" { rime.more() }
    } else {
      error = rime.error.isEmpty ? "拼音引擎未就绪" : rime.error
    }
    render()
  }
  private func shouldUppercase() -> Bool {
    if shift || capsLock { return true }
    guard englishBuffer.isEmpty, settings.capitalize, !editingLocalText else { return false }
    let before =
      textDocumentProxy.documentContextBeforeInput?.trimmingCharacters(in: .whitespaces) ?? ""
    return before.isEmpty || ".!?。！？\n".contains(before.last!)
  }
  private func backspace() {
    if !rime.preedit.isEmpty {
      let committed = rime.delete()
      if rime.preedit.isEmpty && !editingLocalText {
        // unmarkText alone commits the previous marked syllable. Removing the
        // final phonetic key must first replace that marked range with empty.
        textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
      }
      apply(committed)
    } else if !englishBuffer.isEmpty {
      englishBuffer.removeLast()
      if !editingLocalText {
        textDocumentProxy.setMarkedText(
          englishBuffer, selectedRange: NSRange(location: englishBuffer.utf16.count, length: 0))
        if englishBuffer.isEmpty { textDocumentProxy.unmarkText() }
      }
    } else if editingLocalText {
      if draftCursor > 0 {
        let index = draft.index(draft.startIndex, offsetBy: draftCursor - 1)
        draft.remove(at: index)
        draftCursor -= 1
      }
    } else {
      textDocumentProxy.deleteBackward()
    }
    tracker.invalidate()
    render()
  }
  private func deleteKey() -> InputKey {
    let b = key("⌫", special: true, immediate: true) { [weak self] in self?.backspace() }
    b.enableDeleteRepeat()
    return b
  }
  private func space() {
    if !rime.preedit.isEmpty {
      flush()
      lastSpace = .distantPast
    } else {
      if !englishBuffer.isEmpty { flush() }
      let now = Date()
      let before = editingLocalText
        ? String(draft.prefix(draftCursor)) : textDocumentProxy.documentContextBeforeInput ?? ""
      if settings.doubleSpace && now.timeIntervalSince(lastSpace) < 0.35 && before.hasSuffix(" ") {
        if editingLocalText {
          draft.remove(at: draft.index(draft.startIndex, offsetBy: draftCursor - 1))
          draftCursor -= 1
        } else {
          textDocumentProxy.deleteBackward()
        }
        insert(english ? ". " : "。")
        lastSpace = .distantPast
      } else {
        insert(" ")
        lastSpace = now
      }
    }
    render()
  }
  private func spaceKey() -> InputKey {
    let b = key("空格") { [weak self] in self?.space() }
    var configuration = UIButton.Configuration.plain()
    configuration.title = "空格"
    configuration.image = UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12))
    configuration.imagePlacement = .trailing
    configuration.imagePadding = 5
    configuration.baseForegroundColor = ink
    configuration.contentInsets = .zero
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
      var attributes = attributes; attributes.font = .systemFont(ofSize: 18); return attributes
    }
    b.configuration = configuration
    b.accessibilityLabel = "空格"
    b.accessibilityIdentifier = "keyboardSpace"
    b.accessibilityHint = "长按说话，松开识别，上滑取消"
    b.holdAction = { [weak self] in self?.startVoice() }
    b.holdMoved = { [weak self] cancel in
      guard let self, self.voiceRequest != nil, !self.voiceFinishing else { return }
      self.voiceCancelOnRelease = cancel
      self.voiceStatusLabel?.text = cancel ? "松开取消" : "正在听，松开完成 · 上滑取消"
    }
    b.holdEnded = { [weak self] cancel in
      if cancel { self?.cancelVoice() } else { self?.finishVoice() }
    }
    return b
  }
  private var enterTitle: String {
    if numberPad || !english && settings.layout == "九宫格拼音" { return "发送" }
    if editingLocalText { return "换行" }
    switch textDocumentProxy.returnKeyType ?? .default {
    case .go: return "前往"
    case .search, .google, .yahoo: return "搜索"
    case .next: return "下一步"
    case .done: return "完成"
    case .continue: return "继续"
    case .send: return "发送"
    default: return "换行"
    }
  }
  private func enterKey() -> InputKey {
    let b = key(enterTitle, primary: true) { [weak self] in
      self?.flush()
      self?.insert("\n")
      self?.render()
    }
    b.accessibilityIdentifier = "keyboardEnter"
    b.holdAction = { [weak self] in
      self?.insert("\n")
      self?.render()
    }
    return b
  }
  private func t9Key(_ title: String, digit: String) -> InputKey {
    let button = key(title, immediate: true) { [weak self] in self?.type(digit) }
    button.accessibilityIdentifier = "t9Key." + digit
    return button
  }
  private func nineKey(includeSpelling: Bool = true) {
    renderingHeight -= compact ? 28 : 51
    if punctuation {
      row(
        settings.symbols.map { s in
          key(s) { [weak self] in
            guard let self else { return }
            let fresh = punctuationInserted && Date().timeIntervalSince(punctuationTime) < 3
            let matching =
              editingLocalText
              ? draftCursor == draft.count && draft.hasSuffix("，")
              : textDocumentProxy.documentContextBeforeInput == punctuationContext
                && punctuationContext?.hasSuffix("，") == true
                && textDocumentProxy.selectedText?.isEmpty != false
            if fresh && matching { backspace() }
            punctuationInserted = false
            insert(s)
            punctuation = false
            render()
          }
        }, height: 31)
    }
    if kaomoji {
      row(
        KeyboardPalette.kaomoji.map { v in
          key(v) { [weak self] in
            if v != "关闭" { self?.insert(v) }
            self?.kaomoji = false
            self?.render()
          }
        }, height: 30)
    }
    if includeSpelling && !rime.preedit.isEmpty {
      spellingBar()
      renderingHeight += 35
    }
    row([
      key("123", special: true) { [weak self] in
        self?.flush()
        self?.numberPad = true
        self?.render()
      },
      key("，。?!") { [weak self] in
        self?.flush()
        self?.insert("，")
        self?.punctuationInserted = true
        self?.punctuationTime = Date()
        self?.punctuationContext = self?.textDocumentProxy.documentContextBeforeInput
        self?.punctuation.toggle()
        self?.render()
      }, t9Key("ABC", digit: "2"),
      t9Key("DEF", digit: "3"), deleteKey(),
    ])
    row([
      key("#@¥", special: true) { [weak self] in
        self?.flush()
        self?.symbolPage = 1
        self?.render()
      }, t9Key("GHI", digit: "4"),
      t9Key("JKL", digit: "5"), t9Key("MNO", digit: "6"),
      key("^_^") { [weak self] in
        self?.kaomoji.toggle()
        self?.render()
      },
    ])
    let third: [UIView] = [
      key("ABC", special: true) { [weak self] in
        self?.flush()
        self?.english = true
        self?.render()
      }, t9Key("PQRS", digit: "7"),
      t9Key("TUV", digit: "8"), t9Key("WXYZ", digit: "9"),
    ]
    let fourth: [UIView] = [
      key("☺", special: true) { [weak self] in
        self?.flush()
        self?.emoji = true
        self?.render()
      },
      key("选拼音") { [weak self] in
        self?.expanded = true
        self?.rime.more()
        self?.render()
      }, spaceKey(),
    ]
    var cells: [(UIView, Int, Int, Int, Int)] = []
    for (i, value) in third.enumerated() { cells.append((value, i, 0, 1, 1)) }
    cells.append((enterKey(), 4, 0, 1, 2))
    cells.append((fourth[0], 0, 1, 1, 1))
    cells.append((fourth[1], 1, 1, 1, 1))
    cells.append((fourth[2], 2, 1, 2, 1))
    grid(cells, rows: 2)
  }
  private func numberKeyboard() {
    renderingHeight -= compact ? 28 : 51
    let rows = [["拼音", "1", "2", "3", "⌫"], ["#@¥", "4", "5", "6", "更多"],
      ["ABC", "7", "8", "9"], ["☺", "，", "0", "空格"]]
    var cells: [(UIView, Int, Int, Int, Int)] = []
    for (r, values) in rows.enumerated() {
      for (c, value) in values.enumerated() {
        let button: InputKey
        if value == "⌫" { button = deleteKey() }
        else if value == "空格" { button = spaceKey() }
        else {
          button = key(value, special: ["拼音", "#@¥", "ABC", "更多"].contains(value), immediate: value.allSatisfy(\.isNumber)) { [weak self] in
            guard let self else { return }
            switch value {
            case "拼音": numberPad = false; english = false
            case "#@¥", "更多": symbolPage = 1
            case "ABC": english = true; numberPad = false
            case "☺": emoji = true
            default: insert(value)
            }
            render()
          }
        }
        cells.append((button, c, r, 1, 1))
      }
    }
    cells.append((enterKey(), 4, 2, 1, 2))
    grid(cells)
  }
  private func letterKey(_ letter: String, uppercase: Bool) -> InputKey {
    let button = key(uppercase ? letter.uppercased() : letter, immediate: true) { [weak self] in
      self?.type(letter)
    }
    letterKeys.append((button, letter))
    return button
  }
  private func qwerty() {
    renderingHeight -= compact ? 28 : 51
    let uppercase = !english || shouldUppercase()
    if !english {
      row(
        "1234567890".map { c in
          key(String(c), immediate: true) { [weak self] in
            self?.flush()
            self?.insert(String(c))
            self?.render()
          }
        }, height: 34)
    }
    for line in ["qwertyuiop", "asdfghjkl"] {
      row(
        line.map { value in
          let s = String(value)
          return letterKey(s, uppercase: uppercase)
        }, widthRatio: line.count == 9 ? 0.9 : 1)
    }
    var third: [UIView] = [
      key(english ? "⇧" : "'词", special: true) { [weak self] in
        guard let self else { return }
        if english {
          let now = Date()
          capsLock = now.timeIntervalSince(lastShift) < 0.35
          shift = capsLock || !shift
          lastShift = now
        } else {
          type("'")
        }
        render()
      }
    ]
    third += "zxcvbnm".map { c in
      let s = String(c)
      return letterKey(s, uppercase: uppercase)
    }
    third.append(deleteKey())
    row(third)
    row([
      key("123", special: true) { [weak self] in
        self?.flush()
        self?.symbolPage = 0
        self?.render()
      },
      key("☺", special: true) { [weak self] in
        self?.flush()
        self?.emoji = true
        self?.render()
      },
      key("中/EN", special: true) { [weak self] in
        self?.flush()
        self?.english.toggle()
        self?.render()
      }, spaceKey(), enterKey(),
    ])
  }
  private let symbols = KeyboardPalette.symbols
  private func symbolsKeyboard(page: Int) {
    for line in symbols[page] {
      row(
        line.map { c in
          return key(c) { [weak self] in self?.insert(c) }
        })
    }
    row([
      key("‹", special: true) { [weak self] in
        self?.symbolPage = (page + 2) % 3
        self?.render()
      }, key("\(page+1)/3", special: true) {},
      key("›", special: true) { [weak self] in
        self?.symbolPage = (page + 1) % 3
        self?.render()
      }, spaceKey(), deleteKey(), enterKey(),
    ])
    row(
      [
        key("返回拼音", special: true) { [weak self] in
          self?.symbolPage = nil
          self?.numberPad = false
          self?.english = false
          self?.render()
        }
      ], height: 30)
  }
  private let emojis = KeyboardPalette.emojis
  private func emojiKeyboard() {
    let names = KeyboardPalette.emojiNames
    row(
      names.enumerated().map { i, n in
        key(n, special: true, primary: emojiCategory == i) { [weak self] in
          self?.emojiCategory = i
          self?.emojiPage = 0
          self?.render()
        }
      }, height: 32)
    let values = emojis[emojiCategory]
    let pages = max(1, (values.count + 27) / 28)
    for r in 0..<4 {
      row(
        (0..<7).map { c in
          let i = emojiPage * 28 + r * 7 + c
          let text = i < values.count ? values[i] : ""
          return key(text) { [weak self] in self?.insert(text) }
        }, height: 38)
    }
    row(
      [
        key("返回键盘", special: true) { [weak self] in
          self?.emoji = false
          self?.render()
        },
        key("‹", special: true) { [weak self] in
          self?.emojiPage = max(0, (self?.emojiPage ?? 0) - 1)
          self?.render()
        }, key("\(emojiPage+1)/\(pages)", special: true) {},
        key("›", special: true) { [weak self] in
          self?.emojiPage = min(pages - 1, (self?.emojiPage ?? 0) + 1)
          self?.render()
        }, deleteKey(),
      ], height: 32)
  }
  private func expandedCandidates() {
    let scroll = UIScrollView()
    let lines = UIStackView()
    lines.axis = .vertical
    lines.spacing = 5
    let values = candidateChoices()
    for start in stride(from: 0, to: values.count, by: 4) {
      let r = UIStackView(
        arrangedSubviews: values[start..<min(start + 4, values.count)].map { c in
          key(c.text) { [weak self] in self?.choose(c) }
        })
      r.spacing = 5
      r.distribution = .fillEqually
      r.heightAnchor.constraint(equalToConstant: 40).isActive = true
      lines.addArrangedSubview(r)
    }
    lines.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(lines)
    NSLayoutConstraint.activate([
      lines.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      lines.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      lines.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      lines.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      lines.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
    ])
    stack.addArrangedSubview(scroll)
  }
  private func draftPanel() {
    let card = UIView()
    card.backgroundColor = cardColor
    card.layer.cornerRadius = 15
    let content = UIStackView()
    content.axis = .vertical
    content.spacing = compact ? 4 : 8
    content.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
      content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
      content.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
      content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
    ])
    let text =
      draft.isEmpty && rime.preedit.isEmpty && englishBuffer.isEmpty
      ? "输入你想说的话，AI帮你优化"
      : String(draft.prefix(draftCursor)) + rime.displayPreedit + englishBuffer + "│"
        + String(draft.dropFirst(draftCursor))
    let editor = label(draft.isEmpty && !error.isEmpty ? error : text, size: 13, color: draft.isEmpty ? error.isEmpty ? muted : accent : ink)
    draftEditor = editor
    editor.accessibilityIdentifier = "keyboardAIDraft"
    editor.numberOfLines = 3
    editor.heightAnchor.constraint(equalToConstant: compact ? 22 : 45).isActive = true
    editor.isUserInteractionEnabled = true
    editor.isAccessibilityElement = true
    editor.accessibilityTraits = .staticText
    editor.accessibilityLabel = draft.isEmpty && !error.isEmpty ? error : text
    editor.addGestureRecognizer(
      UITapGestureRecognizer(target: self, action: #selector(draftTapped(_:))))
    content.addArrangedSubview(editor)
    let optimize = key("✨ 优化", primary: true) { [weak self] in self?.generate() }
    optimize.accessibilityIdentifier = "aiDraftGenerate"
    optimize.widthAnchor.constraint(equalToConstant: 82).isActive = true
    let optimizeRow = UIStackView(arrangedSubviews: [UIView(), optimize])
    optimizeRow.heightAnchor.constraint(equalToConstant: compact ? 30 : 40).isActive = true
    content.addArrangedSubview(optimizeRow)
    if !compact {
      let relationLabel = label("对方是你的", size: 11, color: muted)
      relationLabel.heightAnchor.constraint(equalToConstant: 16).isActive = true
      content.addArrangedSubview(relationLabel)
    }
    let scroll = KeyboardStripScrollView()
    let relations = UIStackView()
    relations.spacing = 6
    for name in Product.relations {
      let b = key(name, special: true, primary: name == relation) { [weak self] in
        self?.relation = name
        self?.render()
      }
      b.titleLabel?.font = .systemFont(ofSize: 11)
      b.isSelected = name == relation
      b.accessibilityIdentifier = "aiRelation." + name
      b.widthAnchor.constraint(equalToConstant: 55).isActive = true
      relations.addArrangedSubview(b)
    }
    attachHorizontal(relations, to: scroll)
    scroll.heightAnchor.constraint(equalToConstant: compact ? 20 : 28).isActive = true
    content.addArrangedSubview(scroll)
    stack.addArrangedSubview(card)
    if !rime.preedit.isEmpty || !englishBuffer.isEmpty {
      candidatesBar()
      if typingPrefix == nil { renderingHeight += compact ? 34 : 49 }
    }
  }
  private func updateDraftEditor() {
    let text = draft.isEmpty && rime.preedit.isEmpty && englishBuffer.isEmpty
      ? "输入你想说的话，AI帮你优化"
      : String(draft.prefix(draftCursor)) + rime.displayPreedit + englishBuffer + "│"
        + String(draft.dropFirst(draftCursor))
    let displayed = draft.isEmpty && !error.isEmpty ? error : text
    draftEditor?.text = displayed
    draftEditor?.accessibilityLabel = displayed
    draftEditor?.textColor = draft.isEmpty ? error.isEmpty ? muted : accent : ink
  }
  @objc private func draftTapped(_ gesture: UITapGestureRecognizer) {
    guard let l = gesture.view as? UILabel, rime.preedit.isEmpty else { return }
    let ratio = max(0, min(1, gesture.location(in: l).x / l.bounds.width))
    draftCursor = min(draft.count, Int(CGFloat(draft.count) * ratio))
    render()
  }
  @discardableResult
  private func addPanel(_ items: [UIView], spacing: CGFloat = 12, inset: CGFloat = 14, spacer: Bool = true) -> UIView {
    let card = UIView()
    card.backgroundColor = cardColor
    card.layer.cornerRadius = 16
    let content = UIStackView(arrangedSubviews: items + (spacer ? [UIView()] : []))
    content.axis = .vertical
    content.spacing = spacing
    content.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: inset),
      content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inset),
      content.topAnchor.constraint(equalTo: card.topAnchor, constant: inset),
      content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -inset),
    ])
    card.heightAnchor.constraint(equalToConstant: compact ? 200 : mode == "帮你回" ? (options.isEmpty ? 368 : 300) : mode == "超会说" ? 360 : 270).isActive = true
    stack.addArrangedSubview(card)
    return card
  }
  private func showPrompt(_ title: String, message: String, confirmTitle: String? = nil,
    dismissTitle: String = "关闭", confirm: (() -> Void)? = nil) {
    inlinePrompt = InlinePrompt(title: title, message: message, confirmTitle: confirmTitle,
      confirm: confirm, dismissTitle: dismissTitle)
    render()
  }
  private func promptPanel(_ prompt: InlinePrompt) {
    var content: [UIView] = [label(prompt.title, size: 16, bold: true), label(prompt.message, size: 13, color: muted)]
    if let title = prompt.confirmTitle {
      let button = key(title, primary: true) { [weak self] in
        self?.inlinePrompt = nil
        self?.render()
        prompt.confirm?()
      }
      button.accessibilityIdentifier = "keyboardPromptPrimary"
      button.heightAnchor.constraint(equalToConstant: 44).isActive = true
      content.append(button)
    }
    let dismiss = key(prompt.dismissTitle, special: true) { [weak self] in
      self?.inlinePrompt = nil
      self?.render()
    }
    dismiss.accessibilityIdentifier = "keyboardPromptDismiss"
    dismiss.heightAnchor.constraint(equalToConstant: 44).isActive = true
    content.append(dismiss)
    addPanel(content).accessibilityIdentifier = "keyboardPrompt"
  }
  private func replyPanel() {
    if loading || !options.isEmpty { resultPanel(polish: false); return }
    let paste = key("+  粘贴TA的话", primary: true) { [weak self] in self?.pasteForReply() }
    paste.accessibilityIdentifier = "replyPaste"
    paste.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    paste.heightAnchor.constraint(equalToConstant: compact ? 34 : 44).isActive = true
    let screenshot = key("📷  截图识别回复", special: true) { [weak self] in self?.pickScreenshot() }
    screenshot.accessibilityIdentifier = "replyScreenshot"
    screenshot.backgroundColor = color(dark ? 0x42343A : 0xFFFBFC)
    screenshot.setTitleColor(accent, for: .normal)
    screenshot.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
    screenshot.layer.borderWidth = 1
    screenshot.layer.borderColor = accent.cgColor
    screenshot.heightAnchor.constraint(equalToConstant: compact ? 32 : 44).isActive = true
    addPanel([
      label("帮你回", size: 17, bold: true),
      label("复制对方的话，AI帮你分析并生成回复", size: 13, color: muted),
      paste, screenshot,
      label(error.isEmpty ? "没有TA的原话？直接截聊天图，AI识别后帮你回" : error, size: 12, color: error.isEmpty ? muted : accent),
    ], spacing: 8)
  }
  private func guidePanel() {
    let noAccess = error.contains("完全访问")
    let noModel = error.contains("尚未配置官方模型")
    let unopened = error.contains("请开通 VIP")
    let title = noAccess ? "请允许完全访问" : noModel ? "\(mode)还未绑定模型" : unopened ? "AI 功能还未开通" : "模型服务暂不可用"
    let heading = UIStackView(arrangedSubviews: [label(title, size: 16, bold: true), key("×", special: true) { [weak self] in
      self?.aiGuide = false; self?.error = ""; self?.render()
    }])
    heading.spacing = 8
    heading.arrangedSubviews.last?.widthAnchor.constraint(equalToConstant: 34).isActive = true
    heading.heightAnchor.constraint(equalToConstant: 42).isActive = true
    let hint = noAccess ? "在系统设置中开启恋爱键盘的允许完全访问后重试"
      : noModel ? "可在下方选择已添加的模型，或开通 VIP 使用官方模型"
      : "可在 App 中查看订阅与自配模型设置"
    let first = key(noAccess ? "设置指引" : unopened ? "订阅套餐" : noModel ? "配置模型" : "检查配置", primary: true) { [weak self] in
      self?.openMain(noAccess ? "setup" : unopened ? "subscription" : "models")
    }
    let second = key(noAccess ? "关闭" : unopened ? "配置模型" : "订阅套餐", special: true) { [weak self] in
      if noAccess { self?.aiGuide = false; self?.error = ""; self?.render() }
      else { self?.openMain(unopened ? "models" : "subscription") }
    }
    let buttons = UIStackView(arrangedSubviews: [first, second])
    buttons.spacing = 10
    buttons.distribution = .fillEqually
    buttons.heightAnchor.constraint(equalToConstant: 44).isActive = true
    addPanel([heading, label(error, size: 12, color: muted), label(hint, size: 12, color: muted), buttons])
  }
  private func resultPanel(polish: Bool) {
    let close = key("×", special: true) { [weak self] in
      self?.cancelWork(); self?.options = []; self?.render()
    }
    close.accessibilityIdentifier = "aiResultClose"
    close.widthAnchor.constraint(equalToConstant: 34).isActive = true
    if loading {
      let spinner = UIActivityIndicatorView(style: .large)
      spinner.color = accent
      spinner.startAnimating()
      var items: [UIView] = []
      if !polish {
        let top = UIStackView(arrangedSubviews: [UIView(), close])
        top.heightAnchor.constraint(equalToConstant: 30).isActive = true
        items.append(top)
      }
      items.append(spinner)
      items.append(label(polish ? "AI正在优化..." : "正在分析并生成3条回复...", size: 16, color: accent, bold: true))
      if polish { items.append(label("正在连接大模型，请稍候", size: 13, color: muted)) }
      addPanel(items)
      return
    }
    let title = label(polish ? "AI优化话术（点击选择）" : "😊 " + emotion, size: compact ? 12 : 14, color: accent, bold: true)
    let heading = UIStackView(arrangedSubviews: [title, close])
    heading.spacing = 8
    heading.heightAnchor.constraint(equalToConstant: compact ? 24 : 30).isActive = true
    var items: [UIView] = [heading]
    if !polish {
      let caption = label("AI推荐回复（点击使用）", size: 12, color: accent)
      caption.heightAnchor.constraint(equalToConstant: 14).isActive = true
      items.append(caption)
    }
    for (index, value) in options.prefix(3).enumerated() {
      let button = key(value, special: true) { [weak self] in self?.safeInsert(value) }
      button.accessibilityIdentifier = "aiResult.\(index)"
      button.accessibilityLabel = value
      button.accessibilityHint = "点击填入输入框；选择另一条可替换，不会发送"
      button.titleLabel?.numberOfLines = 1
      button.titleLabel?.lineBreakMode = .byTruncatingTail
      button.titleLabel?.font = .systemFont(ofSize: compact ? 13 : 14)
      button.contentHorizontalAlignment = .left
      button.textPadding = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
      button.heightAnchor.constraint(equalToConstant: compact ? 32 : polish ? 64 : 52).isActive = true
      items.append(button)
    }
    if !polish {
      let retry = key("🔄 重新分析", special: true) { [weak self] in self?.generate() }
      retry.accessibilityIdentifier = "aiReplyReanalyze"
      retry.heightAnchor.constraint(equalToConstant: compact ? 24 : 30).isActive = true
      items.append(retry)
    }
    addPanel(items, spacing: compact ? 4 : 8, inset: compact ? 8 : 12)
  }
  private func pasteForReply() {
    guard hasFullAccess else {
      showError("在线 AI 需要在系统键盘设置中允许完全访问")
      return
    }
    guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
      !text.isEmpty
    else {
      showError("剪贴板没有文字，请先复制TA的话")
      return
    }
    lastSource = text
    recordClipboard(text)
    lastImage = nil
    emotion = Suggestions.emotion(text)
    generate()
  }
  private func pasteText() {
    guard hasFullAccess else {
      showError("粘贴需要在系统键盘设置中允许完全访问")
      return
    }
    guard let text = UIPasteboard.general.string, !text.isEmpty else {
      showError("剪贴板没有文字")
      return
    }
    flush()
    insert(text)
    render()
  }
  private func recordClipboard(_ text: String) {
    guard settings.clipboardHistory, text.count <= 2000,
      !["sk-", "password", "api_key", "token", "密码", "验证码"].contains(where: {
        text.lowercased().contains($0)
      })
    else { return }
    store.settings.clipboard.removeAll { $0.term == text }
    store.settings.clipboard.insert(Word(term: text), at: 0)
    store.settings.clipboard = Array(store.settings.clipboard.prefix(50))
  }
  private func generate() {
    guard hasFullAccess else {
      showError("在线 AI 需要在系统键盘设置中允许完全访问")
      return
    }
    guard settings.aiConsent else {
      showPrompt("允许 AI 处理本次内容？",
        message: "只将你主动选择的消息或草稿发送给官方代理或自配服务商，用于生成回复。日常按键不会上传。",
        confirmTitle: "同意并继续", dismissTitle: "取消") { [weak self] in
          self?.store.settings.aiConsent = true
          self?.generate()
        }
      return
    }
    if editingLocalText { flush() }
    let source = mode == "超会说" ? draft.trimmingCharacters(in: .whitespacesAndNewlines) : lastSource
    guard !source.isEmpty || lastImage != nil else {
      showError(mode == "超会说" ? "请先输入想要优化的话" : "剪贴板没有文字，请先复制TA的话")
      return
    }
    cancelWork()
    let ticket = generation
    guard let target = currentDocument else {
      showError("输入框暂不可用，请重新点选输入框后重试")
      return
    }
    let token = store.token()
    let user = store.user?.id
    let mode = self.mode
    let settings = self.settings
    let image = lastImage
    let relation = relation
    loading = true
    options = []
    error = ""
    aiGuide = false
    render()
    work = Task {
      do {
        let values: [String]
        if let image, mode == "帮你回" {
          let result = try await api.vision(
            image: image, settings: settings, key: KeyboardUITestSupport.modelKey(), token: token)
          values = result.replies
          if generation == ticket { emotion = result.scenario + " · " + result.analysis }
        } else {
          values = try await api.suggestions(
            text: source, relation: mode == "超会说" ? relation : nil, settings: settings,
            key: KeyboardUITestSupport.modelKey(), token: token)
        }
        try Task.checkCancellation()
        guard generation == ticket, self.mode == mode,
          currentDocument == target, store.user?.id == user,
          store.token() == token
        else { return }
        options = values
        loading = false
        render()
      } catch is CancellationError {} catch {
        guard generation == ticket else { return }
        loading = false
        showError(error.localizedDescription)
      }
    }
  }
  private func safeInsert(_ text: String) {
    guard let document, currentDocument == document else {
      showError("输入框已切换，请重新选择结果")
      return
    }
    let count = tracker.replacementDeletionCount(
      before: textDocumentProxy.documentContextBeforeInput, selected: textDocumentProxy.selectedText
    )
    for _ in 0..<count { textDocumentProxy.deleteBackward() }
    textDocumentProxy.insertText(text)
    tracker.remember(text: text, before: textDocumentProxy.documentContextBeforeInput)
  }
  private func showError(_ text: String) {
    error = text
    aiGuide = ["超会说", "帮你回"].contains(mode) && !text.contains("请先输入") && !text.contains("剪贴板没有文字")
    render()
    if mode == "键盘" { showPrompt("恋爱键盘", message: text) }
  }
  private func clipboardPanel() {
    if settings.clipboard.isEmpty {
      stack.addArrangedSubview(label("剪贴板暂无内容", color: muted))
      stack.addArrangedSubview(UIView())
      return
    }
    let scroll = UIScrollView()
    let rows = UIStackView()
    rows.axis = .vertical
    rows.spacing = 6
    for item in settings.clipboard {
      let button = key(item.term, special: true) { [weak self] in self?.safeInsert(item.term) }
      button.accessibilityIdentifier = item.id.uuidString
      button.accessibilityHint = "向左滑动删除"
      let swipe = UISwipeGestureRecognizer(target: self, action: #selector(deleteClipboardRow(_:)))
      swipe.direction = .left
      button.addGestureRecognizer(swipe)
      button.heightAnchor.constraint(equalToConstant: 48).isActive = true
      rows.addArrangedSubview(button)
    }
    rows.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(rows)
    NSLayoutConstraint.activate([
      rows.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      rows.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      rows.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      rows.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      rows.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
    ])
    stack.addArrangedSubview(scroll)
  }
  @objc private func deleteClipboardRow(_ gesture: UISwipeGestureRecognizer) {
    guard let id = gesture.view?.accessibilityIdentifier else { return }
    store.settings.clipboard.removeAll { $0.id.uuidString == id }
    render()
  }
  private func voiceInsertionAnchor() -> VoiceInsertionAnchor? {
    guard let document = currentDocument else { return nil }
    return VoiceInsertionAnchor(document: document, before: textDocumentProxy.documentContextBeforeInput,
      after: textDocumentProxy.documentContextAfterInput, selected: textDocumentProxy.selectedText,
      mode: mode, draft: draft, cursor: draftCursor, account: store.user?.id)
  }
  private func startVoice() {
    updateDocument()
    guard voiceRequest == nil else { return }
    guard hasFullAccess else {
      showVoiceNotice("启用键盘语音", message: "请在系统键盘设置中允许恋爱键盘完全访问。")
      return
    }
    guard let channel = KeyboardVoiceChannel.mailbox(), let state = channel.read(), state.isLive() else {
      UserDefaults(suiteName: Product.group)?.set("voice", forKey: "requestedDestination")
      showVoiceNotice("开启键盘语音", message: "请先在恋爱键盘 App 开启语音会话，再返回长按空格。")
      return
    }
    clearVoiceSetupRequest()
    voicePreparedComposition = !rime.preedit.isEmpty || !englishBuffer.isEmpty
    preparingVoice = true
    flush()
    preparingVoice = false
    guard let anchor = voiceInsertionAnchor() else { showVoiceNotice("语音输入", message: "请重新点选输入框后重试"); return }
    cancelWork()
    inlinePrompt = nil
    voiceRequest = UUID(); voiceSession = state.session; voiceAnchor = anchor
    voiceBegan = Date(); voiceFinishing = false; voiceCancelOnRelease = false
    showVoiceBanner()
    do { try channel.send(KeyboardVoiceCommand(session: state.session, request: voiceRequest!, action: .start)) }
    catch { showVoiceNotice("语音输入", message: "无法启动语音通信，请重试"); return }
    voicePoll = Task { [weak self] in
      while !Task.isCancelled {
        guard let self, let request = self.voiceRequest else { return }
        self.store.reloadUser()
        guard self.hasFullAccess, self.voiceAnchor == self.voiceInsertionAnchor() else {
          self.cancelVoice(); return
        }
        guard let update = channel.read(), update.session == self.voiceSession, update.isLive() else {
          self.showVoiceNotice("语音会话已结束", message: "请在主 App 重新开启语音会话后重试"); return
        }
        if Date().timeIntervalSince(self.voiceHeartbeat) > 0.7 {
          try? channel.send(KeyboardVoiceCommand(session: update.session, request: request, action: .keepAlive))
          self.voiceHeartbeat = Date()
        }
        if update.request == request {
          self.voiceTranscriptLabel?.text = update.text.isEmpty ? "说出你想输入的话…" : update.text
          let seconds = min(60, Int(Date().timeIntervalSince(update.startedAt ?? self.voiceBegan)))
          if update.phase == .processing { self.voiceFinishing = true }
          self.voiceStatusLabel?.text = self.voiceCancelOnRelease ? "松开取消"
            : update.phase == .processing ? "正在识别…" : "正在听 \(seconds)s · 松开完成，上滑取消"
          if update.phase == .result {
            let text = OutputRules.punctuation(update.text, preference: self.settings.punctuation)
            let anchor = self.voiceAnchor
            self.closeVoiceBanner()
            try? channel.send(KeyboardVoiceCommand(session: update.session, request: request, action: .acknowledge))
            guard anchor == self.voiceInsertionAnchor() else { return }
            self.insert(text)
            self.render(); return
          }
          if update.phase == .failed {
            let message = update.message
            self.showVoiceNotice("语音输入", message: message); return
          }
        } else if Date().timeIntervalSince(self.voiceBegan) > 3 {
          self.showVoiceNotice("语音连接超时", message: "请在主 App 重新开启语音会话后重试"); return
        }
        if Date().timeIntervalSince(self.voiceBegan) > 95 {
          self.showVoiceNotice("语音识别超时", message: "请检查网络后重试"); return
        }
        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
      }
    }
  }
  private func finishVoice() {
    guard let request = voiceRequest, let session = voiceSession, !voiceFinishing else { return }
    voiceFinishing = true
    voiceStatusLabel?.text = "正在识别…"
    do { try KeyboardVoiceChannel.mailbox()?.send(KeyboardVoiceCommand(session: session, request: request, action: .finish)) }
    catch { showVoiceNotice("语音输入", message: "无法完成语音通信，请重试") }
  }
  private func clearVoiceSetupRequest() {
    let defaults = UserDefaults(suiteName: Product.group)
    if defaults?.string(forKey: "requestedDestination") == "voice" { defaults?.removeObject(forKey: "requestedDestination") }
  }
  private func showVoiceNotice(_ title: String, message: String) {
    if let request = voiceRequest, let session = voiceSession {
      try? KeyboardVoiceChannel.mailbox()?.send(KeyboardVoiceCommand(session: session, request: request, action: .cancel))
    }
    voicePoll?.cancel(); voicePoll = nil
    voiceRequest = nil; voiceSession = nil; voiceAnchor = nil
    if voiceBanner == nil { showVoiceBanner() }
    voiceStatusLabel?.text = title
    voiceTranscriptLabel?.text = message
  }
  private func cancelVoice() {
    if let request = voiceRequest, let session = voiceSession {
      try? KeyboardVoiceChannel.mailbox()?.send(KeyboardVoiceCommand(session: session, request: request, action: .cancel))
    }
    let refreshComposition = voicePreparedComposition
    closeVoiceBanner()
    if refreshComposition { render() }
  }
  private func closeVoiceBanner() {
    voicePoll?.cancel(); voicePoll = nil
    voiceRequest = nil; voiceSession = nil; voiceAnchor = nil
    voiceBanner?.removeFromSuperview(); voiceBanner = nil
    voiceStatusLabel = nil; voiceTranscriptLabel = nil
    voicePreparedComposition = false
    UIView.performWithoutAnimation {
      voiceBodyHeight?.isActive = false; voiceBodyHeight = nil
      keyboardBodyTop?.isActive = true
      if let original = voiceOriginalHeight { height?.constant = original }
      voiceOriginalHeight = nil
      view.layoutIfNeeded()
    }
  }
  private func showVoiceBanner() {
    if voiceBanner != nil {
      voiceStatusLabel?.text = "正在连接麦克风…"
      voiceTranscriptLabel?.text = "说出你想输入的话…"
      return
    }
    // Keep the exact same key views, gesture recognizer, and body dimensions.
    // The input view grows upward; the bottom-anchored keyboard never reflows.
    view.layoutIfNeeded()
    let bodyHeight = keyboardBody.bounds.height
    let bannerHeight: CGFloat = compact ? 68 : 84
    voiceOriginalHeight = height?.constant
    let banner = UIView(); banner.backgroundColor = bg
    banner.accessibilityIdentifier = "keyboardVoicePanel"
    banner.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(banner); voiceBanner = banner
    let card = UIView(); card.backgroundColor = cardColor; card.layer.cornerRadius = 12
    card.layer.borderWidth = 1; card.layer.borderColor = accent.withAlphaComponent(0.3).cgColor
    card.translatesAutoresizingMaskIntoConstraints = false; banner.addSubview(card)
    let status = label("正在连接麦克风…", size: 12, color: accent, bold: true)
    status.accessibilityIdentifier = "keyboardVoiceStatus"; voiceStatusLabel = status
    let cancel = InputKey("取消", background: keyColor, foreground: ink) { [weak self] in
      guard let self else { return }
      if self.voiceRequest == nil { self.clearVoiceSetupRequest() }
      self.cancelVoice()
    }
    cancel.titleLabel?.font = .systemFont(ofSize: 12)
    cancel.accessibilityIdentifier = "keyboardVoiceCancel"
    cancel.widthAnchor.constraint(equalToConstant: 44).isActive = true
    let title = UIStackView(arrangedSubviews: [status, cancel]); title.spacing = 8
    title.heightAnchor.constraint(equalToConstant: compact ? 24 : 28).isActive = true
    let transcript = label("说出你想输入的话…", size: compact ? 13 : 15)
    transcript.accessibilityIdentifier = "keyboardVoiceTranscript"; voiceTranscriptLabel = transcript
    transcript.translatesAutoresizingMaskIntoConstraints = false
    let scroll = UIScrollView(); scroll.addSubview(transcript)
    if #available(iOS 26.0, *) { scroll.topEdgeEffect.isHidden = true; scroll.bottomEdgeEffect.isHidden = true }
    NSLayoutConstraint.activate([
      transcript.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      transcript.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      transcript.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      transcript.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      transcript.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
    ])
    let content = UIStackView(arrangedSubviews: [title, scroll])
    content.axis = .vertical; content.spacing = 4; content.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(content)
    UIView.performWithoutAnimation {
      keyboardBodyTop?.isActive = false
      voiceBodyHeight = keyboardBody.heightAnchor.constraint(equalToConstant: bodyHeight)
      NSLayoutConstraint.activate([
        voiceBodyHeight!, banner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        banner.trailingAnchor.constraint(equalTo: view.trailingAnchor), banner.topAnchor.constraint(equalTo: view.topAnchor),
        banner.bottomAnchor.constraint(equalTo: keyboardBody.topAnchor), banner.heightAnchor.constraint(equalToConstant: bannerHeight),
        card.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 6),
        card.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -6),
        card.topAnchor.constraint(equalTo: banner.topAnchor, constant: 5),
        card.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -3),
        content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
        content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
        content.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
        content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
      ])
      height?.constant = bodyHeight + bannerHeight
      view.layoutIfNeeded()
    }
  }
  private func openMain(_ destination: String) {
    if hasFullAccess {
      UserDefaults(suiteName: Product.group)?.set(destination, forKey: "requestedDestination")
    }
    guard let url = URL(string: "lianai://" + destination) else { return }
    let explain: @Sendable (Bool) -> Void = { [weak self] opened in
      guard !opened else { return }
      Task { @MainActor in
        guard let self else { return }
        self.showPrompt("请打开恋爱键盘",
          message: self.hasFullAccess
            ? "系统不允许从当前键盘跳转。请手动打开恋爱键盘主 App，将自动进入对应功能。"
            : "请手动打开恋爱键盘主 App，在「我的 → 设置」完成对应配置。")
      }
    }
    if let extensionContext { extensionContext.open(url, completionHandler: explain) }
    else { explain(false) }
  }
  private func pickScreenshot() {
    guard hasFullAccess else {
      showError("截图识别需要允许完全访问")
      return
    }
    guard screenshotPicker == nil else { return }
    var config = PHPickerConfiguration(photoLibrary: .shared())
    config.selectionLimit = 1
    config.filter = .images
    let picker = PHPickerViewController(configuration: config)
    picker.delegate = self
    // Embed the system picker in the extension. Modal presentation temporarily
    // resigns the host input and can leave a system keyboard after cancellation.
    let overlay = UIView()
    overlay.backgroundColor = bg
    overlay.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(overlay)
    NSLayoutConstraint.activate([
      overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      overlay.topAnchor.constraint(equalTo: view.topAnchor),
      overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    let cancel = key("取消截图", special: true) { [weak self] in self?.closeScreenshotPicker() }
    cancel.accessibilityIdentifier = "cancelKeyboardScreenshot"
    cancel.translatesAutoresizingMaskIntoConstraints = false
    overlay.addSubview(cancel)
    addChild(picker)
    picker.view.translatesAutoresizingMaskIntoConstraints = false
    overlay.addSubview(picker.view)
    NSLayoutConstraint.activate([
      cancel.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 8),
      cancel.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -8),
      cancel.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 5),
      cancel.heightAnchor.constraint(equalToConstant: 38),
      picker.view.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
      picker.view.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
      picker.view.topAnchor.constraint(equalTo: cancel.bottomAnchor, constant: 5),
      picker.view.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
    ])
    picker.didMove(toParent: self)
    screenshotPicker = picker
    screenshotOverlay = overlay
  }
  private func closeScreenshotPicker() {
    screenshotPicker?.willMove(toParent: nil)
    screenshotPicker?.view.removeFromSuperview()
    screenshotPicker?.removeFromParent()
    screenshotPicker = nil
    screenshotOverlay?.removeFromSuperview()
    screenshotOverlay = nil
  }
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    closeScreenshotPicker()
    guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self),
      let target = currentDocument else { return }
    let ticket = generation
    let user = store.user?.id
    provider.loadDataRepresentation(forTypeIdentifier: "public.image") { @Sendable [weak self] data, _ in
      guard let data else { return }
      Task { @MainActor in
        guard let self, self.generation == ticket, self.currentDocument == target,
          self.mode == "帮你回", self.store.user?.id == user,
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let thumb = CGImageSourceCreateThumbnailAtIndex(
            source, 0,
            [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceThumbnailMaxPixelSize: 1280,
              kCGImageSourceCreateThumbnailWithTransform: true,
            ] as CFDictionary)
        else { return }
        self.lastImage = UIImage(cgImage: thumb).jpegData(compressionQuality: 0.8)
        self.lastSource = ""
        self.generate()
      }
    }
  }
  private func learn(_ text: String) {
    guard settings.predictions else { return }
    let appended = PredictionEngine.tokens(text)
    guard !appended.isEmpty else { return }
    if settings.predictionLearning {
      let now = Date().timeIntervalSince1970 * 1000
      for (context, target) in PredictionEngine.transitions(previous: predictionTokens, appended: appended) {
        if let index = predictionLearning.firstIndex(where: { $0.context == context && $0.target == target }) {
          predictionLearning[index].useCount = min(Int.max - 1, predictionLearning[index].useCount) + 1
          predictionLearning[index].lastUsedAt = now
        } else {
          predictionLearning.append(PredictionLearning(context: context, target: target, useCount: 1, lastUsedAt: now))
        }
      }
      if predictionLearning.count > 10_000 {
        predictionLearning.sort {
          $0.useCount == $1.useCount ? $0.lastUsedAt > $1.lastUsedAt : $0.useCount > $1.useCount
        }
        predictionLearning = Array(predictionLearning.prefix(10_000))
      }
      if let data = try? JSONEncoder().encode(predictionLearning) { learningDefaults.set(data, forKey: "predictionLearningV2") }
    }
    predictionTokens = Array((predictionTokens + appended).suffix(16))
    predictions = PredictionEngine.suggestions(tokens: predictionTokens, base: InputLexicon.predictionBase,
      enhanced: InputLexicon.predictionEnhanced, learned: settings.predictionLearning ? predictionLearning : [])
  }
  private func recordEnglish(_ word: String) {
    var learned = learningDefaults.dictionary(forKey: "englishLearning") as? [String: Int] ?? [:]
    let key = word.lowercased()
    learned[key] = min(10000, (learned[key] ?? 0) + 1)
    if learned.count > 1000, let least = learned.min(by: { $0.value < $1.value })?.key {
      learned.removeValue(forKey: least)
    }
    learningDefaults.set(learned, forKey: "englishLearning")
  }
  private static func t9(_ pinyin: String) -> String {
    let groups = ["abc", "def", "ghi", "jkl", "mno", "pqrs", "tuv", "wxyz"]
    return pinyin.compactMap { c in groups.firstIndex { $0.contains(c) }.map { String($0 + 2) } }
      .joined()
  }
}
