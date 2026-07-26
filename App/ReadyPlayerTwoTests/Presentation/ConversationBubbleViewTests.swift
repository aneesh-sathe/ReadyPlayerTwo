import AppKit
import CompanionRuntime
import Testing
@testable import ReadyPlayerTwo

@Suite(.serialized)
@MainActor
struct ConversationBubbleViewTests {
  @Test
  func presentsEveryBubbleStateTruthfully() {
    let view = makeView()
    let presentations: [(BubbleState, String, Bool)] = [
      (.hidden, "Conversation hidden", true),
      (.connecting, "Connecting", false),
      (.listening, "Listening", false),
      (.thinking, "Thinking", false),
      (.speaking, "Speaking", false),
      (.muted, "Microphone muted", false),
      (.error("Network unavailable"), "Network unavailable", false),
      (.ending, "Ending conversation", false),
    ]

    for (state, accessibleValue, isHidden) in presentations {
      view.render(state: state, waveformEnergy: 0)

      #expect(view.state == state)
      #expect(view.accessibilityValue() as? String == accessibleValue)
      #expect(view.isHidden == isHidden)
    }
  }

  @Test
  func waveformClampsEnergyAndAnimatesOnlyForAudibleStates() {
    let driver = FakeWaveformAnimationDriver()
    let view = makeView(animationDriver: driver)

    view.render(state: .listening, waveformEnergy: -1)
    #expect(view.displayedWaveformEnergy == 0)
    #expect(!view.isWaveformAnimating)

    view.render(state: .listening, waveformEnergy: 0.75)
    #expect(view.displayedWaveformEnergy == 0.75)
    #expect(view.isWaveformAnimating)
    #expect(driver.startCount == 1)

    let initialPhase = view.waveformAnimationPhase
    driver.tick()
    #expect(view.waveformAnimationPhase > initialPhase)

    view.render(state: .speaking, waveformEnergy: 2)
    #expect(view.displayedWaveformEnergy == 1)
    #expect(driver.startCount == 1)

    view.render(state: .thinking, waveformEnergy: 0.8)
    #expect(view.displayedWaveformEnergy == 0)
    #expect(!view.isWaveformAnimating)
    #expect(driver.stopCount == 1)

    view.render(state: .listening, waveformEnergy: .nan)
    #expect(view.displayedWaveformEnergy == 0)
    #expect(!view.isWaveformAnimating)
  }

  @Test
  func accessibleButtonsExposeMuteRetryAndEndActions() throws {
    var receivedActions: [RecordedBubbleAction] = []
    let view = ConversationBubbleView(
      actions: ConversationBubbleActions(
        setMuted: { receivedActions.append(.setMuted($0)) },
        retry: { receivedActions.append(.retry) },
        end: { receivedActions.append(.end) }
      ),
      waveformAnimationDriver: FakeWaveformAnimationDriver()
    )

    view.render(state: .listening, waveformEnergy: 0)
    let mute = try #require(button(in: view, identifier: "conversation.mute"))
    let end = try #require(button(in: view, identifier: "conversation.end"))
    #expect(mute.accessibilityLabel() == "Mute microphone")
    #expect(end.accessibilityLabel() == "End conversation")
    mute.performClick(nil)
    end.performClick(nil)

    view.render(state: .muted, waveformEnergy: 0)
    let unmute = try #require(
      button(in: view, identifier: "conversation.mute")
    )
    #expect(unmute.accessibilityLabel() == "Unmute microphone")
    unmute.performClick(nil)

    view.render(state: .error("Offline"), waveformEnergy: 0)
    let retry = try #require(
      button(in: view, identifier: "conversation.retry")
    )
    #expect(retry.accessibilityLabel() == "Retry conversation")
    retry.performClick(nil)

    #expect(
      receivedActions == [
        .setMuted(true),
        .end,
        .setMuted(false),
        .retry,
      ]
    )
  }

  @Test
  func intrinsicSizeAndContrastRemainDeterministicAcrossAppearances() {
    let view = makeView()
    let expectedSize = NSSize(width: 320, height: 104)

    view.appearance = NSAppearance(named: .aqua)
    view.refreshAppearance()
    let lightBackground = view.resolvedBackgroundColor
    let lightForeground = view.resolvedForegroundColor

    #expect(view.intrinsicContentSize == expectedSize)
    #expect(contrastRatio(lightBackground, lightForeground) >= 7)

    view.render(state: .error("Retry available"), waveformEnergy: 0)
    view.appearance = NSAppearance(named: .darkAqua)
    view.refreshAppearance()
    let darkBackground = view.resolvedBackgroundColor
    let darkForeground = view.resolvedForegroundColor

    #expect(view.intrinsicContentSize == expectedSize)
    #expect(contrastRatio(darkBackground, darkForeground) >= 7)
    #expect(lightBackground != darkBackground)
  }

  private func makeView(
    animationDriver: any WaveformAnimationDriving =
      FakeWaveformAnimationDriver()
  ) -> ConversationBubbleView {
    ConversationBubbleView(
      actions: ConversationBubbleActions(
        setMuted: { _ in },
        retry: {},
        end: {}
      ),
      waveformAnimationDriver: animationDriver
    )
  }

  private func button(
    in view: NSView,
    identifier: String
  ) -> NSButton? {
    if let button = view as? NSButton,
      button.accessibilityIdentifier() == identifier
    {
      return button
    }

    for subview in view.subviews {
      if let match = button(in: subview, identifier: identifier) {
        return match
      }
    }
    return nil
  }

  private func contrastRatio(_ first: NSColor, _ second: NSColor) -> Double {
    let firstLuminance = relativeLuminance(first)
    let secondLuminance = relativeLuminance(second)
    let lighter = max(firstLuminance, secondLuminance)
    let darker = min(firstLuminance, secondLuminance)
    return (lighter + 0.05) / (darker + 0.05)
  }

  private func relativeLuminance(_ color: NSColor) -> Double {
    let rgb = color.usingColorSpace(.deviceRGB)!
    return 0.2126 * linearized(rgb.redComponent)
      + 0.7152 * linearized(rgb.greenComponent)
      + 0.0722 * linearized(rgb.blueComponent)
  }

  private func linearized(_ component: Double) -> Double {
    if component <= 0.04045 {
      return component / 12.92
    }
    return pow((component + 0.055) / 1.055, 2.4)
  }
}

private enum RecordedBubbleAction: Equatable {
  case setMuted(Bool)
  case retry
  case end
}

@MainActor
private final class FakeWaveformAnimationDriver:
  WaveformAnimationDriving
{
  private var onTick: (@MainActor () -> Void)?
  private(set) var startCount = 0
  private(set) var stopCount = 0

  func start(onTick: @escaping @MainActor () -> Void) {
    startCount += 1
    self.onTick = onTick
  }

  func stop() {
    guard onTick != nil else {
      return
    }

    stopCount += 1
    onTick = nil
  }

  func tick() {
    onTick?()
  }
}
