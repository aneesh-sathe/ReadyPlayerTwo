import AppKit
import CompanionRuntime

@MainActor
struct ConversationBubbleActions {
  let setMuted: @MainActor (Bool) -> Void
  let retry: @MainActor () -> Void
  let end: @MainActor () -> Void
}

@MainActor
protocol WaveformAnimationDriving: AnyObject {
  func start(onTick: @escaping @MainActor () -> Void)
  func stop()
}

@MainActor
final class ConversationBubbleView: NSView {
  private static let fixedIntrinsicSize = NSSize(width: 320, height: 104)

  private let actions: ConversationBubbleActions
  private let statusLabel = NSTextField(labelWithString: "")
  private let muteButton = NSButton()
  private let retryButton = NSButton()
  private let endButton = NSButton()
  private let waveformView: AudioWaveformView

  private(set) var state = BubbleState.hidden
  private(set) var resolvedBackgroundColor = NSColor.white
  private(set) var resolvedForegroundColor = NSColor.black

  var displayedWaveformEnergy: Double {
    waveformView.energy
  }

  var isWaveformAnimating: Bool {
    waveformView.isAnimating
  }

  var waveformAnimationPhase: Double {
    waveformView.phase
  }

  override var isFlipped: Bool {
    true
  }

  override var intrinsicContentSize: NSSize {
    Self.fixedIntrinsicSize
  }

  init(
    actions: ConversationBubbleActions,
    waveformAnimationDriver: any WaveformAnimationDriving =
      TimerWaveformAnimationDriver()
  ) {
    self.actions = actions
    waveformView = AudioWaveformView(
      animationDriver: waveformAnimationDriver
    )

    super.init(
      frame: NSRect(origin: .zero, size: Self.fixedIntrinsicSize)
    )

    configureView()
    configureStatusLabel()
    configureButtons()
    addSubview(statusLabel)
    addSubview(waveformView)
    addSubview(muteButton)
    addSubview(retryButton)
    addSubview(endButton)
    refreshAppearance()
    render(state: .hidden, waveformEnergy: 0)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func layout() {
    super.layout()

    statusLabel.frame = NSRect(x: 16, y: 13, width: 288, height: 22)
    waveformView.frame = NSRect(x: 16, y: 52, width: 72, height: 28)
    muteButton.frame = NSRect(x: 100, y: 50, width: 72, height: 30)
    retryButton.frame = NSRect(x: 180, y: 50, width: 60, height: 30)
    endButton.frame = NSRect(x: 248, y: 50, width: 56, height: 30)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refreshAppearance()
  }

  func render(state: BubbleState, waveformEnergy: Double) {
    self.state = state

    let presentation = Self.presentation(for: state)
    statusLabel.stringValue = presentation.status
    statusLabel.setAccessibilityValue(presentation.accessibilityValue)
    setAccessibilityValue(presentation.accessibilityValue)
    isHidden = state == .hidden

    let canMute = Self.canMute(in: state)
    muteButton.isHidden = !canMute
    muteButton.isEnabled = canMute
    let isMuted = state == .muted
    muteButton.title = isMuted ? "Unmute" : "Mute"
    muteButton.setAccessibilityLabel(
      isMuted ? "Unmute microphone" : "Mute microphone"
    )

    let canRetry = Self.canRetry(in: state)
    retryButton.isHidden = !canRetry
    retryButton.isEnabled = canRetry

    endButton.isHidden = state == .hidden
    endButton.isEnabled = state != .hidden && state != .ending

    let hasAudibleEnergy = state == .listening || state == .speaking
    waveformView.isHidden = !hasAudibleEnergy
    waveformView.setEnergy(hasAudibleEnergy ? waveformEnergy : 0)
  }

  func refreshAppearance() {
    let isDark =
      effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let borderColor: NSColor

    if isDark {
      resolvedBackgroundColor = NSColor(
        deviceWhite: 0.10,
        alpha: 0.97
      )
      resolvedForegroundColor = NSColor(
        deviceWhite: 0.96,
        alpha: 1
      )
      borderColor = NSColor(
        deviceWhite: 0.32,
        alpha: 1
      )
    } else {
      resolvedBackgroundColor = NSColor(
        deviceWhite: 0.97,
        alpha: 0.97
      )
      resolvedForegroundColor = NSColor(
        deviceWhite: 0.08,
        alpha: 1
      )
      borderColor = NSColor(
        deviceWhite: 0.78,
        alpha: 1
      )
    }

    layer?.borderColor = borderColor.cgColor
    layer?.backgroundColor = resolvedBackgroundColor.cgColor
    statusLabel.textColor = resolvedForegroundColor
    waveformView.foregroundColor = resolvedForegroundColor
  }

  private func configureView() {
    wantsLayer = true
    layer?.cornerRadius = 16
    layer?.borderWidth = 1
    layer?.masksToBounds = true

    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("Companion conversation")
    setAccessibilityIdentifier("conversation.bubble")
  }

  private func configureStatusLabel() {
    statusLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    statusLabel.lineBreakMode = .byTruncatingTail
    statusLabel.maximumNumberOfLines = 1
    statusLabel.setAccessibilityElement(true)
    statusLabel.setAccessibilityRole(.staticText)
    statusLabel.setAccessibilityIdentifier("conversation.status")
  }

  private func configureButtons() {
    configure(
      muteButton,
      title: "Mute",
      accessibilityLabel: "Mute microphone",
      identifier: "conversation.mute",
      action: #selector(mutePressed)
    )
    configure(
      retryButton,
      title: "Retry",
      accessibilityLabel: "Retry conversation",
      identifier: "conversation.retry",
      action: #selector(retryPressed)
    )
    configure(
      endButton,
      title: "End",
      accessibilityLabel: "End conversation",
      identifier: "conversation.end",
      action: #selector(endPressed)
    )
  }

  private func configure(
    _ button: NSButton,
    title: String,
    accessibilityLabel: String,
    identifier: String,
    action: Selector
  ) {
    button.title = title
    button.target = self
    button.action = action
    button.bezelStyle = .rounded
    button.controlSize = .small
    button.font = .systemFont(ofSize: 12, weight: .medium)
    button.setAccessibilityElement(true)
    button.setAccessibilityLabel(accessibilityLabel)
    button.setAccessibilityIdentifier(identifier)
  }

  @objc
  private func mutePressed() {
    actions.setMuted(state != .muted)
  }

  @objc
  private func retryPressed() {
    actions.retry()
  }

  @objc
  private func endPressed() {
    actions.end()
  }

  private static func canMute(in state: BubbleState) -> Bool {
    switch state {
    case .connecting, .listening, .thinking, .speaking, .muted:
      true
    case .hidden, .error, .ending:
      false
    }
  }

  private static func canRetry(in state: BubbleState) -> Bool {
    if case .error = state {
      return true
    }
    return false
  }

  private static func presentation(
    for state: BubbleState
  ) -> (status: String, accessibilityValue: String) {
    switch state {
    case .hidden:
      ("Conversation hidden", "Conversation hidden")
    case .connecting:
      ("Connecting", "Connecting")
    case .listening:
      ("Listening", "Listening")
    case .thinking:
      ("Thinking", "Thinking")
    case .speaking:
      ("Speaking", "Speaking")
    case .muted:
      ("Microphone muted", "Microphone muted")
    case .error(let message):
      (
        message.isEmpty ? "Conversation unavailable" : message,
        message.isEmpty ? "Conversation unavailable" : message
      )
    case .ending:
      ("Ending conversation", "Ending conversation")
    }
  }
}

@MainActor
private final class AudioWaveformView: NSView {
  private let animationDriver: any WaveformAnimationDriving

  private(set) var energy = 0.0
  private(set) var phase = 0.0
  private(set) var isAnimating = false
  var foregroundColor = NSColor.labelColor {
    didSet {
      needsDisplay = true
    }
  }

  override var isFlipped: Bool {
    true
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: 72, height: 28)
  }

  init(animationDriver: any WaveformAnimationDriving) {
    self.animationDriver = animationDriver
    super.init(frame: NSRect(x: 0, y: 0, width: 72, height: 28))

    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    foregroundColor.setFill()
    let barWidth = 5.0
    let spacing = 5.0
    let barCount = 7
    let totalWidth =
      Double(barCount) * barWidth + Double(barCount - 1) * spacing
    let firstX = (bounds.width - totalWidth) / 2

    for index in 0..<barCount {
      let oscillation =
        (sin(phase + Double(index) * 0.9) + 1) / 2
      let height =
        4 + energy * (bounds.height - 4)
        * (0.55 + oscillation * 0.45)
      let rect = NSRect(
        x: firstX + Double(index) * (barWidth + spacing),
        y: (bounds.height - height) / 2,
        width: barWidth,
        height: height
      )
      NSBezierPath(
        roundedRect: rect,
        xRadius: barWidth / 2,
        yRadius: barWidth / 2
      ).fill()
    }
  }

  func setEnergy(_ proposedEnergy: Double) {
    energy =
      proposedEnergy.isFinite
      ? min(max(proposedEnergy, 0), 1)
      : 0

    if energy > 0 {
      startAnimatingIfNeeded()
    } else {
      stopAnimatingIfNeeded()
    }
    needsDisplay = true
  }

  private func startAnimatingIfNeeded() {
    guard !isAnimating else {
      return
    }

    isAnimating = true
    animationDriver.start { [weak self] in
      self?.advanceAnimation()
    }
  }

  private func stopAnimatingIfNeeded() {
    guard isAnimating else {
      phase = 0
      return
    }

    isAnimating = false
    animationDriver.stop()
    phase = 0
  }

  private func advanceAnimation() {
    phase = (phase + .pi / 8)
      .truncatingRemainder(dividingBy: .pi * 2)
    needsDisplay = true
  }
}

@MainActor
private final class TimerWaveformAnimationDriver:
  NSObject,
  WaveformAnimationDriving
{
  @MainActor
  private final class WeakTimerTarget: NSObject {
    weak var owner: TimerWaveformAnimationDriver?

    init(owner: TimerWaveformAnimationDriver) {
      self.owner = owner
    }

    @objc
    func fire() {
      owner?.fire()
    }
  }

  private var onTick: (@MainActor () -> Void)?
  private var timer: Timer?
  private lazy var timerTarget = WeakTimerTarget(owner: self)

  isolated deinit {
    timer?.invalidate()
  }

  func start(onTick: @escaping @MainActor () -> Void) {
    stop()
    self.onTick = onTick

    let timer = Timer(
      timeInterval: 1 / 30,
      target: timerTarget,
      selector: #selector(WeakTimerTarget.fire),
      userInfo: nil,
      repeats: true
    )
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    onTick = nil
  }

  private func fire() {
    onTick?()
  }
}
