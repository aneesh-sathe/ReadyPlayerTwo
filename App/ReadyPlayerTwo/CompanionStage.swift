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

@MainActor
final class CompanionStageActions {
  private var summonHandler: (@MainActor () async -> Void)?
  private var dragToParkHandler: (@MainActor (StagePoint) async -> Void)?

  func connect(
    summon: @escaping @MainActor () async -> Void,
    dragToPark: @escaping @MainActor (StagePoint) async -> Void
  ) {
    summonHandler = summon
    dragToParkHandler = dragToPark
  }

  func summon() async {
    await summonHandler?()
  }

  func dragToPark(_ point: StagePoint) async {
    await dragToParkHandler?(point)
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
  private let actions: CompanionStageActions
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

  convenience init(
    bundle: Bundle,
    actions: CompanionStageActions = CompanionStageActions()
  ) {
    guard let resourceURL = bundle.resourceURL else {
      preconditionFailure("The application bundle has no resource directory.")
    }

    do {
      let isHostedUnitTest = CompanionStageEnvironment.isHostedUnitTest
      try self.init(
        assetRootURL: resourceURL,
        actions: actions,
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
    actions: CompanionStageActions = CompanionStageActions(),
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
    self.actions = actions
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
      actions: actions,
      interactiveRegion: renderer.currentHitRegion,
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
      panel.stopPointerTracking()
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
    panel.startPointerTracking()
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
    panel.updateInteractiveRegion(renderer.currentHitRegion)
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
    panel.updateInteractiveRegion(renderer.currentHitRegion)
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
  private var hitRegions: [URL: AlphaHitRegion] = [:]
  private(set) var currentHitRegion: AlphaHitRegion?

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
    currentHitRegion = AlphaHitRegion(image: image)
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
    currentHitRegion = hitRegions[firstFrame]

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
    currentHitRegion = hitRegions[url]
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
    hitRegions[url] = AlphaHitRegion(image: image)
    return texture
  }
}

struct AlphaHitRegion {
  private let width: Int
  private let height: Int
  private let alpha: [UInt8]

  init?(image: NSImage) {
    var proposedRect = NSRect(
      origin: .zero,
      size: image.size
    )
    guard
      let cgImage = image.cgImage(
        forProposedRect: &proposedRect,
        context: nil,
        hints: nil
      )
    else {
      return nil
    }

    let imageWidth = min(cgImage.width, 128)
    let imageHeight = min(cgImage.height, 128)
    var rgba = [UInt8](
      repeating: 0,
      count: imageWidth * imageHeight * 4
    )
    let rendered = rgba.withUnsafeMutableBytes { bytes in
      guard
        let context = CGContext(
          data: bytes.baseAddress,
          width: imageWidth,
          height: imageHeight,
          bitsPerComponent: 8,
          bytesPerRow: imageWidth * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo:
            CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        )
      else {
        return false
      }

      context.draw(
        cgImage,
        in: CGRect(
          x: 0,
          y: 0,
          width: imageWidth,
          height: imageHeight
        )
      )
      return true
    }
    guard rendered else {
      return nil
    }

    width = imageWidth
    height = imageHeight
    alpha = stride(from: 3, to: rgba.count, by: 4).map {
      rgba[$0]
    }
  }

  func contains(
    _ point: NSPoint,
    in viewSize: NSSize,
    padding: CGFloat = 4
  ) -> Bool {
    guard
      viewSize.width > 0,
      viewSize.height > 0,
      point.x >= 0,
      point.y >= 0,
      point.x < viewSize.width,
      point.y < viewSize.height
    else {
      return false
    }

    let pixelX = min(
      width - 1,
      max(0, Int(point.x / viewSize.width * CGFloat(width)))
    )
    let pixelY = min(
      height - 1,
      max(0, Int(point.y / viewSize.height * CGFloat(height)))
    )
    let horizontalRadius = Int(
      ceil(padding / viewSize.width * CGFloat(width))
    )
    let verticalRadius = Int(
      ceil(padding / viewSize.height * CGFloat(height))
    )

    for y in max(0, pixelY - verticalRadius)...min(height - 1, pixelY + verticalRadius) {
      for x in max(0, pixelX - horizontalRadius)...min(width - 1, pixelX + horizontalRadius)
      where alpha[y * width + x] > 12 {
        return true
      }
    }
    return false
  }
}

@MainActor
private final class CompanionInteractionView: NSView {
  var onClick: (@MainActor () -> Void)?
  var onDragPreview: (@MainActor (StagePoint) -> Void)?
  var onDragFinished: (@MainActor (StagePoint) -> Void)?

  private var mouseDownScreenPoint: NSPoint?
  private var didDrag = false

  override func mouseDown(with event: NSEvent) {
    mouseDownScreenPoint = NSEvent.mouseLocation
    didDrag = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard let mouseDownScreenPoint else {
      return
    }
    let location = NSEvent.mouseLocation
    let distance = hypot(
      location.x - mouseDownScreenPoint.x,
      location.y - mouseDownScreenPoint.y
    )
    if distance >= 3 {
      didDrag = true
    }
    if didDrag {
      onDragPreview?(
        StagePoint(x: location.x, y: location.y)
      )
    }
  }

  override func mouseUp(with event: NSEvent) {
    defer {
      mouseDownScreenPoint = nil
      didDrag = false
    }

    let location = NSEvent.mouseLocation
    if didDrag {
      onDragFinished?(
        StagePoint(x: location.x, y: location.y)
      )
    } else {
      onClick?()
    }
  }
}

@MainActor
final class CompanionPanel: NSPanel {
  private let actions: CompanionStageActions
  private let canvasSize: NSSize
  private let interactionView: CompanionInteractionView
  private weak var spriteView: SKView?
  private var interactiveRegion: AlphaHitRegion?
  private var pointerTrackingTimer: Timer?

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
      actions: CompanionStageActions(),
      interactiveRegion: renderer.currentHitRegion,
      presentsScene: hostsSpriteView,
      hostsSpriteView: hostsSpriteView
    )
  }

  init(
    scene: SKScene,
    canvasSize: NSSize,
    actions: CompanionStageActions,
    interactiveRegion: AlphaHitRegion? = nil,
    presentsScene: Bool,
    hostsSpriteView: Bool
  ) {
    let contentRect = NSRect(origin: .zero, size: canvasSize)
    self.actions = actions
    self.canvasSize = canvasSize
    self.interactiveRegion = interactiveRegion
    interactionView = CompanionInteractionView(frame: contentRect)

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

    let rootView = NSView(frame: contentRect)
    rootView.autoresizingMask = [.width, .height]

    if hostsSpriteView {
      let spriteView = SKView(frame: contentRect)
      spriteView.allowsTransparency = true
      spriteView.autoresizingMask = [.width, .height]
      if presentsScene {
        spriteView.presentScene(scene)
      }
      rootView.addSubview(spriteView)
      self.spriteView = spriteView
    }

    interactionView.autoresizingMask = [.width, .height]
    rootView.addSubview(interactionView)
    contentView = rootView

    interactionView.onClick = { [weak self] in
      self?.performCharacterClick()
    }
    interactionView.onDragPreview = { [weak self] point in
      self?.previewCharacterDrag(to: point)
    }
    interactionView.onDragFinished = { [weak self] point in
      self?.performCharacterDrag(to: point)
    }
  }

  func present(scene: SKScene) {
    guard let spriteView else {
      return
    }
    guard spriteView.scene !== scene else {
      return
    }

    spriteView.presentScene(scene)
  }

  func updateInteractiveRegion(_ region: AlphaHitRegion?) {
    interactiveRegion = region
  }

  func updateMousePassthrough(atScreenPoint point: NSPoint) {
    let localPoint = NSPoint(
      x: point.x - frame.minX,
      y: point.y - frame.minY
    )
    ignoresMouseEvents = !isInteractive(at: localPoint)
  }

  func isInteractive(at localPoint: NSPoint) -> Bool {
    interactiveRegion?.contains(
      localPoint,
      in: canvasSize,
      padding: 4
    ) ?? false
  }

  func performCharacterClick() {
    Task { @MainActor [weak actions] in
      await actions?.summon()
    }
  }

  func performCharacterDrag(to point: StagePoint) {
    Task { @MainActor [weak actions] in
      await actions?.dragToPark(point)
    }
  }

  func startPointerTracking() {
    guard pointerTrackingTimer == nil else {
      return
    }

    let timer = Timer(
      timeInterval: 1.0 / 30.0,
      target: self,
      selector: #selector(refreshPointerPassthrough),
      userInfo: nil,
      repeats: true
    )
    RunLoop.main.add(timer, forMode: .common)
    pointerTrackingTimer = timer
    refreshPointerPassthrough()
  }

  func stopPointerTracking() {
    pointerTrackingTimer?.invalidate()
    pointerTrackingTimer = nil
    ignoresMouseEvents = true
  }

  @objc
  private func refreshPointerPassthrough() {
    updateMousePassthrough(atScreenPoint: NSEvent.mouseLocation)
  }

  private func previewCharacterDrag(to point: StagePoint) {
    ignoresMouseEvents = false
    setFrameOrigin(
      NSPoint(
        x: point.x - canvasSize.width / 2,
        y: point.y - canvasSize.height / 2
      )
    )
  }
}
