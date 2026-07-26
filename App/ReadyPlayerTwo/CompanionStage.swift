import AppKit
import CompanionRuntime
import SpriteKit

private enum CompanionStageEnvironment {
  static var isHostedUnitTest: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
      || NSClassFromString("XCTestCase") != nil
      || Bundle.allBundles.contains(where: {
        $0.bundlePath.hasSuffix(".xctest")
      })
  }
}

struct CompanionStageSurface {
  let visibleFrame: NSRect
  let scaleFactor: CGFloat
}

@MainActor
protocol CompanionStageTerrain {
  func surface(for placement: CompanionPlacement) -> CompanionStageSurface
}

@MainActor
struct ScreenCompanionStageTerrain: CompanionStageTerrain {
  func surface(for placement: CompanionPlacement) -> CompanionStageSurface {
    let point = NSPoint(
      x: placement.position.x,
      y: placement.position.y
    )
    let display =
      NSScreen.screens.first(where: {
        let number =
          $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
          as? NSNumber
        return number?.stringValue == placement.displayID
      })
      ?? NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
      ?? NSScreen.main
      ?? NSScreen.screens.first

    return CompanionStageSurface(
      visibleFrame: display?.visibleFrame ?? .zero,
      scaleFactor: display?.backingScaleFactor ?? 1
    )
  }
}

@MainActor
protocol CompanionStageFrameDriving: AnyObject {
  func start(tick: @escaping (TimeInterval) -> Void)
  func stop()
}

@MainActor
final class CompanionSpriteScene: SKScene {
  var frameTick: ((TimeInterval) -> Void)?
  private var previousUpdateTime: TimeInterval?

  override func update(_ currentTime: TimeInterval) {
    defer {
      previousUpdateTime = currentTime
    }
    guard let previousUpdateTime else {
      return
    }

    let elapsed = min(max(currentTime - previousUpdateTime, 0), 0.1)
    frameTick?(elapsed)
  }

  func resetFrameClock() {
    previousUpdateTime = nil
  }
}

@MainActor
final class SceneCompanionStageFrameDriver: CompanionStageFrameDriving {
  private weak var scene: CompanionSpriteScene?

  init(scene: CompanionSpriteScene) {
    self.scene = scene
  }

  func start(tick: @escaping (TimeInterval) -> Void) {
    scene?.resetFrameClock()
    scene?.frameTick = tick
  }

  func stop() {
    scene?.frameTick = nil
    scene?.resetFrameClock()
  }
}

@MainActor
protocol CompanionStageMotionPreference {
  var shouldReduceMotion: Bool { get }
}

@MainActor
struct SystemCompanionStageMotionPreference:
  CompanionStageMotionPreference
{
  var shouldReduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }
}

enum CompanionAssets {
  static let orionNeutralRelativePath =
    "assets/avatar-orion/expressions/warrior-front-neutral.png"

  static func avatarRootURL(
    for avatar: CompanionAvatar,
    under assetRootURL: URL
  ) -> URL {
    let directory =
      switch avatar {
      case .orion:
        "avatar-orion"
      case .athena:
        "avatar-athena"
      }

    return assetRootURL.appending(path: "assets/\(directory)")
  }

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
  private static let roamingBurstDuration = 2.4
  private static let roamingHoldDuration = 3.0

  let panel: CompanionPanel
  private let renderer: CompanionSpriteRenderer
  private let manifests: [CompanionAvatar: AvatarAnimationManifest]
  private let terrain: any CompanionStageTerrain
  private let frameDriver: any CompanionStageFrameDriving
  private let motionPreference: any CompanionStageMotionPreference
  private let motionPlanner = MotionPlanner()
  private let panelPresentationEnabled: Bool
  private var latestSnapshot: CompanionSnapshot?
  private var lastRuntimePlacement: CompanionPlacement?
  private var activeStepIndex = 0
  private var animationElapsed = 0.0
  private var burstElapsed = 0.0
  private var holdRemaining = 0.0

  private(set) var presentedAvatar = CompanionAvatar.orion
  private(set) var currentMotionPlan: MotionPlan?
  private(set) var currentAnimationState: AnimationStateID?
  private(set) var currentFrameURLs: [URL] = []
  private(set) var characterCenter = StagePoint(x: 0, y: 0)
  private(set) var lastCrossfadeDuration = 0.0

  var availableAvatars: Set<CompanionAvatar> {
    Set(manifests.keys)
  }

  var scene: SKScene {
    renderer.scene
  }

  convenience init(bundle: Bundle) {
    guard let resourceURL = bundle.resourceURL else {
      preconditionFailure("The application bundle has no resource directory.")
    }

    do {
      let isHostedUnitTest = CompanionStageEnvironment.isHostedUnitTest
      try self.init(
        assetRootURL: resourceURL,
        panelPresentationEnabled: !isHostedUnitTest,
        hostsSpriteView: !isHostedUnitTest
      )
    } catch {
      preconditionFailure(
        "Invalid bundled companion assets: \(error)"
      )
    }
  }

  init(
    assetRootURL: URL,
    terrain: any CompanionStageTerrain = ScreenCompanionStageTerrain(),
    frameDriver suppliedFrameDriver:
      (any CompanionStageFrameDriving)? = nil,
    motionPreference: any CompanionStageMotionPreference =
      SystemCompanionStageMotionPreference(),
    panelPresentationEnabled: Bool = true,
    hostsSpriteView: Bool = true
  ) throws {
    let loader = AnimationManifestLoader()
    let loadedManifests = try Dictionary(
      uniqueKeysWithValues: CompanionAvatar.allCases.map { avatar in
        (
          avatar,
          try loader.load(
            avatar: avatar,
            from: CompanionAssets.avatarRootURL(
              for: avatar,
              under: assetRootURL
            )
          )
        )
      }
    )
    guard
      let neutralURL = loadedManifests[.orion]?
        .animation(named: "front-neutral")?.frames.first,
      let image = NSImage(contentsOf: neutralURL)
    else {
      throw CocoaError(.fileReadCorruptFile)
    }

    manifests = loadedManifests
    self.terrain = terrain
    self.motionPreference = motionPreference
    self.panelPresentationEnabled = panelPresentationEnabled
    renderer = CompanionSpriteRenderer(
      image: image,
      canvasSize: Self.canvasSize
    )
    frameDriver =
      suppliedFrameDriver
      ?? SceneCompanionStageFrameDriver(scene: renderer.scene)
    panel = CompanionPanel(
      scene: renderer.scene,
      canvasSize: Self.canvasSize,
      presentsScene: false,
      hostsSpriteView: hostsSpriteView
    )
  }

  func render(_ snapshot: CompanionSnapshot) async {
    let avatarChanged = snapshot.avatar != presentedAvatar
    presentedAvatar = snapshot.avatar

    guard snapshot.isVisible else {
      stopMotion()
      latestSnapshot = snapshot
      lastRuntimePlacement = snapshot.placement
      panel.orderOut(nil)
      return
    }

    if lastRuntimePlacement != snapshot.placement || latestSnapshot == nil {
      characterCenter = snapshot.placement.position
    }
    lastRuntimePlacement = snapshot.placement
    latestSnapshot = snapshot
    updateSpacePolicy(for: snapshot)

    switch snapshot.voice {
    case .idle:
      if snapshot.basePresence == .roaming,
        !motionPreference.shouldReduceMotion
      {
        startRoamingIfNeeded(avatarChanged: avatarChanged)
      } else {
        stopMotion()
        showAnimation(
          named: "front-neutral",
          avatarChanged: avatarChanged
        )
      }
    case .speaking:
      stopMotion()
      showAnimation(
        named: "front-happy",
        avatarChanged: avatarChanged
      )
    case .connecting, .listening, .thinking, .muted, .error, .ending:
      stopMotion()
      showAnimation(
        named: "front-neutral",
        avatarChanged: avatarChanged
      )
    }

    positionPanel()

    guard
      panelPresentationEnabled,
      !CompanionStageEnvironment.isHostedUnitTest
    else {
      return
    }

    panel.present(scene: renderer.scene)
    panel.orderFrontRegardless()
  }

  private func startRoamingIfNeeded(avatarChanged: Bool) {
    guard currentMotionPlan == nil else {
      if avatarChanged {
        beginRoamingPlan()
      }
      return
    }

    if holdRemaining > 0 {
      showAnimation(
        named: "front-neutral",
        avatarChanged: avatarChanged
      )
    } else {
      beginRoamingPlan(avatarChanged: avatarChanged)
    }

    frameDriver.start { [weak self] elapsed in
      self?.advance(by: elapsed)
    }
  }

  private func beginRoamingPlan(avatarChanged: Bool = false) {
    guard
      let snapshot = latestSnapshot,
      let manifest = manifests[snapshot.avatar]
    else {
      return
    }

    let surface = terrain.surface(for: snapshot.placement)
    let midpoint = surface.visibleFrame.midX
    let direction: HorizontalDirection =
      characterCenter.x <= midpoint ? .right : .left
    guard
      let plan = try? motionPlanner.plan(
        .walk(direction),
        using: manifest
      ),
      let firstStep = plan.steps.first
    else {
      return
    }

    currentMotionPlan = plan
    activeStepIndex = 0
    burstElapsed = 0
    showAnimation(
      named: firstStep.state.rawValue,
      avatarChanged: avatarChanged
    )
  }

  private func advance(by elapsed: TimeInterval) {
    guard elapsed.isFinite, elapsed > 0, let snapshot = latestSnapshot else {
      return
    }
    guard
      snapshot.isVisible,
      snapshot.basePresence == .roaming,
      snapshot.voice == .idle
    else {
      stopMotion()
      return
    }

    if holdRemaining > 0 {
      holdRemaining = max(0, holdRemaining - elapsed)
      if holdRemaining == 0 {
        beginRoamingPlan()
      }
      positionPanel()
      return
    }

    guard
      let plan = currentMotionPlan,
      plan.steps.indices.contains(activeStepIndex)
    else {
      beginRoamingPlan()
      return
    }

    let step = plan.steps[activeStepIndex]
    apply(step.translation, elapsed: elapsed, snapshot: snapshot)
    advanceAnimation(by: elapsed)
    burstElapsed += elapsed

    if burstElapsed >= Self.roamingBurstDuration {
      currentMotionPlan = nil
      holdRemaining = Self.roamingHoldDuration
      showAnimation(named: "front-neutral", avatarChanged: false)
    }

    positionPanel()
  }

  private func apply(
    _ translation: MotionTranslation,
    elapsed: TimeInterval,
    snapshot: CompanionSnapshot
  ) {
    var translated = characterCenter

    switch translation {
    case .stationary:
      break
    case .groundedWalk(let direction, let pointsPerSecond):
      let sign = direction == .left ? -1.0 : 1.0
      translated.x += sign * pointsPerSecond * elapsed
    case .vertical(let direction, let pointsPerSecond):
      let sign = direction == .down ? -1.0 : 1.0
      translated.y += sign * pointsPerSecond * elapsed
    case .slowAirborneDrift(let direction, let pointsPerSecond):
      let sign = direction == .left ? -1.0 : 1.0
      translated.x += sign * pointsPerSecond * elapsed
    }

    let surface = terrain.surface(for: snapshot.placement)
    let clamped = StageRect(
      origin: StagePoint(
        x: surface.visibleFrame.origin.x,
        y: surface.visibleFrame.origin.y
      ),
      size: StageSize(
        width: surface.visibleFrame.width,
        height: surface.visibleFrame.height
      )
    ).clamped(translated, inset: Self.canvasSize.width / 2)

    if clamped != translated {
      currentMotionPlan = nil
      holdRemaining = 0
    }
    characterCenter = clamped
  }

  private func advanceAnimation(by elapsed: TimeInterval) {
    guard
      let snapshot = latestSnapshot,
      let state = currentAnimationState,
      let animation = manifests[snapshot.avatar]?.animations[state]
    else {
      return
    }

    animationElapsed += elapsed
    let rawIndex = Int(animationElapsed * animation.framesPerSecond)
    let frameIndex =
      animation.loops
      ? rawIndex % animation.frames.count
      : min(rawIndex, animation.frames.count - 1)
    renderer.showFrame(at: animation.frames[frameIndex])
  }

  private func showAnimation(
    named name: String,
    avatarChanged: Bool
  ) {
    guard
      let manifest = manifests[presentedAvatar],
      let animation = manifest.animation(named: name)
    else {
      return
    }

    currentAnimationState = animation.id
    currentFrameURLs = animation.frames
    animationElapsed = 0
    lastCrossfadeDuration = avatarChanged ? 0.2 : 0
    renderer.showAnimation(
      animation,
      crossfadeDuration: lastCrossfadeDuration
    )
  }

  private func stopMotion() {
    frameDriver.stop()
    currentMotionPlan = nil
    activeStepIndex = 0
    animationElapsed = 0
    burstElapsed = 0
    holdRemaining = 0
  }

  private func positionPanel() {
    guard let snapshot = latestSnapshot else {
      return
    }

    let rawOrigin = NSPoint(
      x: characterCenter.x - Self.canvasSize.width / 2,
      y: characterCenter.y - Self.canvasSize.height / 2
    )
    let surface = terrain.surface(for: snapshot.placement)
    let scaleFactor = max(surface.scaleFactor, 1)
    let origin = NSPoint(
      x: (rawOrigin.x * scaleFactor).rounded() / scaleFactor,
      y: (rawOrigin.y * scaleFactor).rounded() / scaleFactor
    )
    panel.setFrameOrigin(origin)
  }

  private func updateSpacePolicy(for snapshot: CompanionSnapshot) {
    panel.collectionBehavior =
      snapshot.voice == .idle
      ? [.moveToActiveSpace]
      : [.moveToActiveSpace, .fullScreenAuxiliary]
  }
}

@MainActor
final class CompanionSpriteRenderer {
  let scene: CompanionSpriteScene
  private let canvasSize: NSSize
  private var sprite: SKSpriteNode
  private var textures: [URL: SKTexture] = [:]

  init(image: NSImage, canvasSize: NSSize) {
    let scene = CompanionSpriteScene(size: canvasSize)
    scene.backgroundColor = .clear
    scene.scaleMode = .resizeFill

    let texture = SKTexture(image: image)
    texture.filteringMode = .nearest
    let sprite = SKSpriteNode(texture: texture, size: canvasSize)
    sprite.position = CGPoint(
      x: canvasSize.width / 2,
      y: canvasSize.height / 2
    )
    scene.addChild(sprite)

    self.canvasSize = canvasSize
    self.sprite = sprite
    self.scene = scene
  }

  func showAnimation(
    _ animation: SpriteAnimation,
    crossfadeDuration: TimeInterval
  ) {
    guard let firstFrame = animation.frames.first else {
      return
    }
    guard let texture = texture(for: firstFrame) else {
      return
    }

    if crossfadeDuration > 0 {
      let outgoing = sprite
      let incoming = SKSpriteNode(texture: texture, size: canvasSize)
      incoming.position = outgoing.position
      incoming.alpha = 0
      scene.addChild(incoming)
      incoming.run(.fadeIn(withDuration: crossfadeDuration))
      outgoing.run(.fadeOut(withDuration: crossfadeDuration)) {
        outgoing.removeFromParent()
      }
      sprite = incoming
    } else {
      sprite.texture = texture
      sprite.alpha = 1
    }
  }

  func showFrame(at url: URL) {
    guard let texture = texture(for: url) else {
      return
    }
    sprite.texture = texture
  }

  private func texture(for url: URL) -> SKTexture? {
    if let cached = textures[url] {
      return cached
    }
    guard let image = NSImage(contentsOf: url) else {
      return nil
    }

    let texture = SKTexture(image: image)
    texture.filteringMode = .nearest
    textures[url] = texture
    return texture
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

  convenience init(image: NSImage, canvasSize: NSSize) {
    let renderer = CompanionSpriteRenderer(
      image: image,
      canvasSize: canvasSize
    )
    let hostsSpriteView = !CompanionStageEnvironment.isHostedUnitTest
    self.init(
      scene: renderer.scene,
      canvasSize: canvasSize,
      presentsScene: hostsSpriteView,
      hostsSpriteView: hostsSpriteView
    )
  }

  init(
    scene: SKScene,
    canvasSize: NSSize,
    presentsScene: Bool,
    hostsSpriteView: Bool
  ) {
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

    if hostsSpriteView {
      let spriteView = SKView(frame: contentRect)
      spriteView.allowsTransparency = true
      spriteView.autoresizingMask = [.width, .height]
      if presentsScene {
        spriteView.presentScene(scene)
      }
      contentView = spriteView
    } else {
      let headlessView = NSView(frame: contentRect)
      headlessView.autoresizingMask = [.width, .height]
      contentView = headlessView
    }
  }

  func present(scene: SKScene) {
    guard let spriteView = contentView as? SKView else {
      return
    }
    guard spriteView.scene !== scene else {
      return
    }

    spriteView.presentScene(scene)
  }
}
