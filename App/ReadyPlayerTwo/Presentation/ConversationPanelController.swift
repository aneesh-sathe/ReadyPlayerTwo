import AppKit
import CompanionRuntime

@MainActor
protocol ConversationPresenting: AnyObject {
  func render(_ snapshot: CompanionSnapshot)
}

@MainActor
protocol ConversationVisibleFrameResolving {
  func visibleFrame(for placement: CompanionPlacement) -> StageRect
}

@MainActor
struct ScreenConversationVisibleFrameResolver:
  ConversationVisibleFrameResolving
{
  func visibleFrame(for placement: CompanionPlacement) -> StageRect {
    let point = NSPoint(
      x: placement.position.x,
      y: placement.position.y
    )
    let screen =
      NSScreen.screens.first(where: {
        let number =
          $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
          as? NSNumber
        return number?.stringValue == placement.displayID
      })
      ?? NSScreen.screens.first(where: {
        NSMouseInRect(point, $0.frame, false)
      })
      ?? NSScreen.main
      ?? NSScreen.screens.first

    guard let screen else {
      return CompanionDisplay.main.visibleFrame
    }

    let frame = screen.visibleFrame
    return StageRect(
      origin: StagePoint(x: frame.origin.x, y: frame.origin.y),
      size: StageSize(width: frame.width, height: frame.height)
    )
  }
}

@MainActor
final class ConversationPanelController: ConversationPresenting {
  fileprivate static let bubbleSize = NSSize(width: 320, height: 104)
  private static let companionSize = 128.0
  private static let bubbleGap = 12.0

  let panel: NSPanel
  private let bubbleView: ConversationBubbleView
  private let visibleFrameResolver: any ConversationVisibleFrameResolving

  init(
    actions: ConversationBubbleActions,
    waveformAnimationDriver: (any WaveformAnimationDriving)? = nil,
    visibleFrameResolver: any ConversationVisibleFrameResolving =
      ScreenConversationVisibleFrameResolver()
  ) {
    let bubbleView =
      if let waveformAnimationDriver {
        ConversationBubbleView(
          actions: actions,
          waveformAnimationDriver: waveformAnimationDriver
        )
      } else {
        ConversationBubbleView(actions: actions)
      }
    self.bubbleView = bubbleView
    self.visibleFrameResolver = visibleFrameResolver
    panel = ConversationPanel(contentView: bubbleView)
  }

  func render(_ snapshot: CompanionSnapshot) {
    render(
      state: snapshot.bubble,
      waveformEnergy: snapshot.waveformEnergy,
      companionCenter: snapshot.placement.position,
      visibleFrame: visibleFrameResolver.visibleFrame(
        for: snapshot.placement
      )
    )
  }

  func render(
    state: BubbleState,
    waveformEnergy: Double,
    companionCenter: StagePoint,
    visibleFrame: StageRect
  ) {
    bubbleView.render(state: state, waveformEnergy: waveformEnergy)

    guard state != .hidden else {
      panel.orderOut(nil)
      return
    }

    let origin = Self.bubbleOrigin(
      beside: companionCenter,
      inside: visibleFrame
    )
    panel.setFrame(
      NSRect(
        x: origin.x,
        y: origin.y,
        width: Self.bubbleSize.width,
        height: Self.bubbleSize.height
      ),
      display: false
    )
    panel.orderFrontRegardless()
  }

  private static func bubbleOrigin(
    beside companionCenter: StagePoint,
    inside visibleFrame: StageRect
  ) -> StagePoint {
    let companionRadius = companionSize / 2
    let bubbleWidth = Double(bubbleSize.width)
    let bubbleHeight = Double(bubbleSize.height)
    let sideY = companionCenter.y - bubbleHeight / 2
    let rightOrigin = StagePoint(
      x: companionCenter.x + companionRadius + bubbleGap,
      y: sideY
    )
    let leftOrigin = StagePoint(
      x:
        companionCenter.x - companionRadius - bubbleGap
        - bubbleWidth,
      y: sideY
    )
    let aboveOrigin = StagePoint(
      x: companionCenter.x - bubbleWidth / 2,
      y: companionCenter.y + companionRadius + bubbleGap
    )

    let selectedOrigin =
      if fitsHorizontally(rightOrigin, inside: visibleFrame) {
        rightOrigin
      } else if fitsHorizontally(leftOrigin, inside: visibleFrame) {
        leftOrigin
      } else {
        aboveOrigin
      }

    return clamped(selectedOrigin, inside: visibleFrame)
  }

  private static func fitsHorizontally(
    _ origin: StagePoint,
    inside visibleFrame: StageRect
  ) -> Bool {
    origin.x >= visibleFrame.origin.x
      && origin.x + Double(bubbleSize.width)
        <= visibleFrame.origin.x + visibleFrame.size.width
  }

  private static func clamped(
    _ origin: StagePoint,
    inside visibleFrame: StageRect
  ) -> StagePoint {
    let maximumX = max(
      visibleFrame.origin.x,
      visibleFrame.origin.x + visibleFrame.size.width
        - Double(bubbleSize.width)
    )
    let maximumY = max(
      visibleFrame.origin.y,
      visibleFrame.origin.y + visibleFrame.size.height
        - Double(bubbleSize.height)
    )

    return StagePoint(
      x: min(max(origin.x, visibleFrame.origin.x), maximumX),
      y: min(max(origin.y, visibleFrame.origin.y), maximumY)
    )
  }

  isolated deinit {
    panel.orderOut(nil)
  }
}

@MainActor
private final class ConversationPanel: NSPanel {
  override var canBecomeKey: Bool {
    false
  }

  override var canBecomeMain: Bool {
    false
  }

  init(contentView: ConversationBubbleView) {
    super.init(
      contentRect: NSRect(
        origin: .zero,
        size: ConversationPanelController.bubbleSize
      ),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    backgroundColor = .clear
    isOpaque = false
    isReleasedWhenClosed = false
    isFloatingPanel = true
    becomesKeyOnlyIfNeeded = true
    hidesOnDeactivate = false
    ignoresMouseEvents = false
    level = .floating
    animationBehavior = .none
    collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    self.contentView = contentView
  }
}
