import AppKit
import CompanionRuntime

enum CompanionAssets {
  static let orionNeutralRelativePath =
    "assets/avatar-orion/expressions/warrior-front-neutral.png"

  static func orionNeutralURL(in bundle: Bundle) -> URL? {
    guard let resourceURL = bundle.resourceURL else {
      return nil
    }

    let url = resourceURL.appending(path: orionNeutralRelativePath)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  static func orionNeutralImage(in bundle: Bundle) -> NSImage? {
    guard let url = orionNeutralURL(in: bundle) else {
      return nil
    }

    return NSImage(contentsOf: url)
  }
}

@MainActor
final class CompanionStage: StagePort {
  static let canvasSize = NSSize(width: 128, height: 128)

  private let panel: CompanionPanel

  init(bundle: Bundle) {
    guard let image = CompanionAssets.orionNeutralImage(in: bundle) else {
      preconditionFailure(
        "Missing bundled sprite: \(CompanionAssets.orionNeutralRelativePath)"
      )
    }

    panel = CompanionPanel(image: image, canvasSize: Self.canvasSize)
  }

  func render(_ snapshot: CompanionSnapshot) async {
    guard snapshot.isVisible else {
      panel.orderOut(nil)
      return
    }

    let origin = NSPoint(
      x: snapshot.placement.position.x - Self.canvasSize.width / 2,
      y: snapshot.placement.position.y - Self.canvasSize.height / 2
    )
    panel.setFrameOrigin(origin)
    panel.orderFrontRegardless()
  }
}

@MainActor
final class CompanionPanel: NSPanel {
  override var canBecomeKey: Bool {
    false
  }

  override var canBecomeMain: Bool {
    false
  }

  init(image: NSImage, canvasSize: NSSize) {
    let contentRect = NSRect(origin: .zero, size: canvasSize)

    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    isReleasedWhenClosed = false
    isFloatingPanel = true
    becomesKeyOnlyIfNeeded = true
    hidesOnDeactivate = false
    ignoresMouseEvents = true
    level = .floating
    collectionBehavior = [.moveToActiveSpace]
    animationBehavior = .none

    let imageView = NSImageView(frame: contentRect)
    imageView.image = image
    imageView.imageAlignment = .alignCenter
    imageView.imageFrameStyle = .none
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.autoresizingMask = [.width, .height]
    contentView = imageView
  }
}
