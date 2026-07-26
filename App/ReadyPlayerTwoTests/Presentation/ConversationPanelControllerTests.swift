import AppKit
import CompanionRuntime
import Testing

@testable import ReadyPlayerTwo

@Suite(.serialized)
@MainActor
struct ConversationPanelControllerTests {
  @Test
  func runtimeSnapshotUsesItsPlacementDisplayVisibleFrame() {
    let visibleFrame = StageRect(
      origin: StagePoint(x: -1_440, y: 25),
      size: StageSize(width: 1_440, height: 850)
    )
    let resolver = PanelVisibleFrameResolver(visibleFrame: visibleFrame)
    let controller = ConversationPanelController(
      actions: ConversationBubbleActions(
        setMuted: { _ in },
        retry: {},
        end: {}
      ),
      waveformAnimationDriver: PanelWaveformAnimationDriver(),
      visibleFrameResolver: resolver
    )
    let snapshot = CompanionSnapshot(
      avatar: .athena,
      basePresence: .parked,
      isVisible: true,
      placement: CompanionPlacement(
        displayID: "external",
        position: StagePoint(x: -200, y: 850)
      ),
      voice: .speaking,
      bubble: .speaking,
      waveformEnergy: 0.8,
      recoverableError: nil
    )

    controller.render(snapshot)
    defer {
      controller.panel.orderOut(nil)
    }

    #expect(resolver.placements == [snapshot.placement])
    #expect(
      controller.panel.frame
        == NSRect(x: -596, y: 771, width: 320, height: 104)
    )
  }

  @Test
  func visibleConversationAppearsBesideTheCompanion() throws {
    let controller = ConversationPanelController(
      actions: ConversationBubbleActions(
        setMuted: { _ in },
        retry: {},
        end: {}
      ),
      waveformAnimationDriver: PanelWaveformAnimationDriver()
    )

    controller.render(
      state: .listening,
      waveformEnergy: 0.7,
      companionCenter: StagePoint(x: 500, y: 400),
      visibleFrame: StageRect(
        origin: StagePoint(x: 0, y: 0),
        size: StageSize(width: 1_440, height: 900)
      )
    )
    defer {
      controller.render(
        state: .hidden,
        waveformEnergy: 0,
        companionCenter: StagePoint(x: 500, y: 400),
        visibleFrame: StageRect(
          origin: StagePoint(x: 0, y: 0),
          size: StageSize(width: 1_440, height: 900)
        )
      )
    }

    #expect(
      controller.panel.frame
        == NSRect(x: 576, y: 348, width: 320, height: 104)
    )
    #expect(controller.panel.isVisible)

    let bubble = try #require(
      controller.panel.contentView as? ConversationBubbleView
    )
    #expect(bubble.state == .listening)
    #expect(bubble.displayedWaveformEnergy == 0.7)
  }

  @Test
  func negativeCoordinateDisplayUsesTheAvailableCompanionSide() {
    let controller = ConversationPanelController(
      actions: ConversationBubbleActions(
        setMuted: { _ in },
        retry: {},
        end: {}
      ),
      waveformAnimationDriver: PanelWaveformAnimationDriver()
    )

    controller.render(
      state: .connecting,
      waveformEnergy: 0,
      companionCenter: StagePoint(x: -100, y: 400),
      visibleFrame: StageRect(
        origin: StagePoint(x: -1_600, y: 0),
        size: StageSize(width: 1_600, height: 900)
      )
    )

    #expect(
      controller.panel.frame
        == NSRect(x: -496, y: 348, width: 320, height: 104)
    )
  }

  @Test
  func conversationMovesAboveWhenNeitherSideFits() {
    let controller = ConversationPanelController(
      actions: ConversationBubbleActions(
        setMuted: { _ in },
        retry: {},
        end: {}
      ),
      waveformAnimationDriver: PanelWaveformAnimationDriver()
    )

    controller.render(
      state: .thinking,
      waveformEnergy: 0,
      companionCenter: StagePoint(x: 350, y: 400),
      visibleFrame: StageRect(
        origin: StagePoint(x: 0, y: 0),
        size: StageSize(width: 700, height: 900)
      )
    )

    #expect(
      controller.panel.frame
        == NSRect(x: 190, y: 476, width: 320, height: 104)
    )
  }

  @Test
  func conversationClampsToNegativeVisibleFrameBelowTheMenuBar() {
    let controller = ConversationPanelController(
      actions: ConversationBubbleActions(
        setMuted: { _ in },
        retry: {},
        end: {}
      ),
      waveformAnimationDriver: PanelWaveformAnimationDriver()
    )

    controller.render(
      state: .speaking,
      waveformEnergy: 1,
      companionCenter: StagePoint(x: -200, y: 850),
      visibleFrame: StageRect(
        origin: StagePoint(x: -1_440, y: 25),
        size: StageSize(width: 1_440, height: 850)
      )
    )

    #expect(
      controller.panel.frame
        == NSRect(x: -596, y: 771, width: 320, height: 104)
    )
  }

  @Test
  func hiddenConversationOrdersOutTheExistingPanel() throws {
    let controller = ConversationPanelController(
      actions: ConversationBubbleActions(
        setMuted: { _ in },
        retry: {},
        end: {}
      ),
      waveformAnimationDriver: PanelWaveformAnimationDriver()
    )
    let originalPanel = controller.panel
    let center = StagePoint(x: 500, y: 400)
    let visibleFrame = StageRect(
      origin: StagePoint(x: 0, y: 0),
      size: StageSize(width: 1_440, height: 900)
    )

    controller.render(
      state: .speaking,
      waveformEnergy: 0.9,
      companionCenter: center,
      visibleFrame: visibleFrame
    )
    #expect(originalPanel.isVisible)

    controller.render(
      state: .hidden,
      waveformEnergy: 0.9,
      companionCenter: center,
      visibleFrame: visibleFrame
    )

    #expect(controller.panel === originalPanel)
    #expect(!originalPanel.isVisible)
    let bubble = try #require(
      originalPanel.contentView as? ConversationBubbleView
    )
    #expect(bubble.state == .hidden)
    #expect(bubble.displayedWaveformEnergy == 0)
  }

  @Test
  func bubblePanelFloatsWithoutTakingFocusOrCoveringTheDesktop() {
    let controller = ConversationPanelController(
      actions: ConversationBubbleActions(
        setMuted: { _ in },
        retry: {},
        end: {}
      ),
      waveformAnimationDriver: PanelWaveformAnimationDriver()
    )
    let keyWindowBeforePresentation = NSApp.keyWindow

    controller.render(
      state: .connecting,
      waveformEnergy: 0,
      companionCenter: StagePoint(x: 500, y: 400),
      visibleFrame: StageRect(
        origin: StagePoint(x: 0, y: 0),
        size: StageSize(width: 1_440, height: 900)
      )
    )
    defer {
      controller.panel.orderOut(nil)
    }

    let panel = controller.panel
    #expect(panel.styleMask.contains(.borderless))
    #expect(panel.styleMask.contains(.nonactivatingPanel))
    #expect(panel.isFloatingPanel)
    #expect(panel.level == .floating)
    #expect(!panel.canBecomeKey)
    #expect(!panel.canBecomeMain)
    #expect(!panel.isKeyWindow)
    #expect(!panel.isMainWindow)
    #expect(NSApp.keyWindow === keyWindowBeforePresentation)
    #expect(!panel.isOpaque)
    #expect(panel.backgroundColor == .clear)
    #expect(!panel.ignoresMouseEvents)
    #expect(panel.frame.size == NSSize(width: 320, height: 104))
    #expect(
      panel.contentView?.frame
        == NSRect(x: 0, y: 0, width: 320, height: 104)
    )
    #expect(panel.collectionBehavior.contains(.moveToActiveSpace))
    #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
  }

  @Test
  func hostedBubbleRoutesMuteRetryAndEndToInjectedActions() throws {
    var receivedActions: [PanelAction] = []
    let controller = ConversationPanelController(
      actions: ConversationBubbleActions(
        setMuted: { receivedActions.append(.setMuted($0)) },
        retry: { receivedActions.append(.retry) },
        end: { receivedActions.append(.end) }
      ),
      waveformAnimationDriver: PanelWaveformAnimationDriver()
    )
    let center = StagePoint(x: 500, y: 400)
    let visibleFrame = StageRect(
      origin: StagePoint(x: 0, y: 0),
      size: StageSize(width: 1_440, height: 900)
    )

    controller.render(
      state: .listening,
      waveformEnergy: 0,
      companionCenter: center,
      visibleFrame: visibleFrame
    )
    let bubble = try #require(
      controller.panel.contentView as? ConversationBubbleView
    )
    let mute = try #require(
      panelButton(in: bubble, identifier: "conversation.mute")
    )
    let end = try #require(
      panelButton(in: bubble, identifier: "conversation.end")
    )
    mute.performClick(nil)
    end.performClick(nil)

    controller.render(
      state: .error("Connection lost"),
      waveformEnergy: 0,
      companionCenter: center,
      visibleFrame: visibleFrame
    )
    let retry = try #require(
      panelButton(in: bubble, identifier: "conversation.retry")
    )
    retry.performClick(nil)

    #expect(receivedActions == [.setMuted(true), .end, .retry])
  }
}

private enum PanelAction: Equatable {
  case setMuted(Bool)
  case retry
  case end
}

@MainActor
private func panelButton(
  in view: NSView,
  identifier: String
) -> NSButton? {
  if let button = view as? NSButton,
    button.accessibilityIdentifier() == identifier
  {
    return button
  }

  for subview in view.subviews {
    if let match = panelButton(in: subview, identifier: identifier) {
      return match
    }
  }
  return nil
}

@MainActor
private final class PanelWaveformAnimationDriver:
  WaveformAnimationDriving
{
  func start(onTick _: @escaping @MainActor () -> Void) {}

  func stop() {}
}

@MainActor
private final class PanelVisibleFrameResolver:
  ConversationVisibleFrameResolving
{
  let visibleFrame: StageRect
  private(set) var placements: [CompanionPlacement] = []

  init(visibleFrame: StageRect) {
    self.visibleFrame = visibleFrame
  }

  func visibleFrame(for placement: CompanionPlacement) -> StageRect {
    placements.append(placement)
    return visibleFrame
  }
}
