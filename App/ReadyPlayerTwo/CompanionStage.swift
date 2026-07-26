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
protocol CompanionStageAnimationDriving: AnyObject {
  func fade(
    _ panel: NSPanel,
    to alphaValue: CGFloat,
    duration: TimeInterval,
    completion: @escaping @MainActor () -> Void
  )
  func cancelFades(for panel: NSPanel)
}

@MainActor
final class AppKitCompanionStageAnimationDriver:
  CompanionStageAnimationDriving
{
  func fade(
    _ panel: NSPanel,
    to alphaValue: CGFloat,
    duration: TimeInterval,
    completion: @escaping @MainActor () -> Void
  ) {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      context.timingFunction = CAMediaTimingFunction(
        name: .easeInEaseOut
      )
      panel.animator().alphaValue = alphaValue
    } completionHandler: {
      MainActor.assumeIsolated {
        completion()
      }
    }
  }

  func cancelFades(for panel: NSPanel) {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0
      panel.animator().alphaValue = panel.alphaValue
    }
  }
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
protocol CompanionStageRoamingIntentSelecting: AnyObject {
  func nextIntent(
    for avatar: CompanionAvatar,
    at characterCenter: StagePoint,
    within surface: CompanionStageSurface
  ) -> MotionIntent
}

@MainActor
final class CapabilityCompanionStageRoamingIntentSelector:
  CompanionStageRoamingIntentSelecting
{
  private enum OrionPhase {
    case approach(HorizontalDirection)
    case cling(edge: HorizontalDirection)
    case jump(edge: HorizontalDirection)
    case land(edge: HorizontalDirection)
  }

  private enum AthenaPhase {
    case walk(HorizontalDirection)
    case takeoff(HorizontalDirection)
    case glideUp(facing: HorizontalDirection)
    case hover(facing: HorizontalDirection)
    case drift(facing: HorizontalDirection)
    case glideDown(facing: HorizontalDirection)
    case land(HorizontalDirection)
  }

  private var orionPhase = OrionPhase.approach(.right)
  private var athenaPhase = AthenaPhase.walk(.right)

  func nextIntent(
    for avatar: CompanionAvatar,
    at characterCenter: StagePoint,
    within surface: CompanionStageSurface
  ) -> MotionIntent {
    switch avatar {
    case .orion:
      return nextOrionIntent(
        at: characterCenter,
        within: surface
      )
    case .athena:
      return nextAthenaIntent(
        at: characterCenter,
        within: surface
      )
    }
  }

  private func nextOrionIntent(
    at characterCenter: StagePoint,
    within surface: CompanionStageSurface
  ) -> MotionIntent {
    switch orionPhase {
    case .approach(let direction):
      guard isAtEdge(direction, characterCenter, surface) else {
        return .walk(direction)
      }
      orionPhase = .cling(edge: direction)
      return .climbUp(entryFrom: direction)

    case .cling(let edge):
      orionPhase = .jump(edge: edge)
      return .cling

    case .jump(let edge):
      orionPhase = .land(edge: edge)
      return .jumpDown(landingToward: inwardDirection(from: edge))

    case .land(let edge):
      let inward = inwardDirection(from: edge)
      orionPhase = .approach(inward)
      return .land(inward)
    }
  }

  private func nextAthenaIntent(
    at characterCenter: StagePoint,
    within surface: CompanionStageSurface
  ) -> MotionIntent {
    switch athenaPhase {
    case .walk(let direction):
      athenaPhase = .takeoff(direction)
      return .walk(direction)

    case .takeoff(let direction):
      athenaPhase = .glideUp(facing: direction)
      return .takeoff(direction)

    case .glideUp(let facing):
      athenaPhase = .hover(facing: facing)
      return .glide(.up)

    case .hover(let facing):
      athenaPhase = .drift(facing: facing)
      return .hover

    case .drift(let facing):
      athenaPhase = .glideDown(facing: facing)
      let safeDirection: HorizontalDirection =
        characterCenter.x <= surface.visibleFrame.midX ? .right : .left
      return .slowDrift(safeDirection)

    case .glideDown(let facing):
      athenaPhase = .land(facing)
      return .glide(.down)

    case .land(let direction):
      athenaPhase = .walk(inwardDirection(from: direction))
      return .land(direction)
    }
  }

  private func isAtEdge(
    _ direction: HorizontalDirection,
    _ characterCenter: StagePoint,
    _ surface: CompanionStageSurface
  ) -> Bool {
    let safeInset = CompanionStage.canvasSize.width / 2
    let target =
      direction == .left
      ? surface.visibleFrame.minX + safeInset
      : surface.visibleFrame.maxX - safeInset
    return abs(characterCenter.x - target) <= 0.5
  }

  private func inwardDirection(
    from edge: HorizontalDirection
  ) -> HorizontalDirection {
    edge == .left ? .right : .left
  }
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
  private static let poseCrossfadeDuration = 0.1
  private static let relocationFadePhaseDuration = 0.1
  private static let clockEpsilon = 0.000_001

  let panel: CompanionPanel
  private let renderer: CompanionSpriteRenderer
  private let manifests: [CompanionAvatar: AvatarAnimationManifest]
  private let terrain: any CompanionStageTerrain
  private let frameDriver: any CompanionStageFrameDriving
  private let animationDriver: any CompanionStageAnimationDriving
  private let motionPreference: any CompanionStageMotionPreference
  private let roamingIntentSelector: any CompanionStageRoamingIntentSelecting
  private let actions: CompanionStageActions
  private let motionPlanner = MotionPlanner()
  private let panelPresentationEnabled: Bool
  private var latestSnapshot: CompanionSnapshot?
  private var lastRuntimePlacement: CompanionPlacement?
  private var activeStepIndex = 0
  private var animationElapsed = 0.0
  private var burstElapsed = 0.0
  private var holdRemaining = 0.0
  private var quietHoldAnimationState = AnimationStateID("front-neutral")
  private var relocationGeneration = 0
  private var isRelocating = false
  private var relocationPositionedPlacement: CompanionPlacement?

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
    animationDriver: any CompanionStageAnimationDriving =
      AppKitCompanionStageAnimationDriver(),
    motionPreference: any CompanionStageMotionPreference =
      SystemCompanionStageMotionPreference(),
    roamingIntentSelector: any CompanionStageRoamingIntentSelecting =
      CapabilityCompanionStageRoamingIntentSelector(),
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
    self.animationDriver = animationDriver
    self.motionPreference = motionPreference
    self.roamingIntentSelector = roamingIntentSelector
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
    panel.updateAccessibilityPresentation(
      avatar: snapshot.avatar,
      presence: snapshot.basePresence
    )

    guard snapshot.isVisible else {
      relocationGeneration &+= 1
      isRelocating = false
      relocationPositionedPlacement = nil
      animationDriver.cancelFades(for: panel)
      panel.alphaValue = 1
      stopMotion()
      latestSnapshot = snapshot
      lastRuntimePlacement = snapshot.placement
      panel.stopPointerTracking()
      panel.orderOut(nil)
      return
    }

    if isRelocating {
      lastRuntimePlacement = snapshot.placement
      latestSnapshot = snapshot
      updateSpacePolicy(for: snapshot)
      if let positionedPlacement = relocationPositionedPlacement,
        positionedPlacement != snapshot.placement
      {
        relocationGeneration &+= 1
        let generation = relocationGeneration
        animationDriver.cancelFades(for: panel)
        panel.alphaValue = 0
        characterCenter = snapshot.placement.position
        relocationPositionedPlacement = snapshot.placement
        positionPanel()
        beginRelocationFadeIn(generation: generation)
      }
      return
    }

    let crossesDisplays =
      latestSnapshot?.isVisible == true
      && lastRuntimePlacement?.displayID != snapshot.placement.displayID
    if crossesDisplays {
      lastRuntimePlacement = snapshot.placement
      latestSnapshot = snapshot
      updateSpacePolicy(for: snapshot)
      beginCrossDisplayRelocation()
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
      settleForConversation(snapshot)
      stopMotion()
      showAnimation(
        named: "front-happy",
        avatarChanged: avatarChanged
      )
    case .connecting, .listening, .thinking, .muted, .error, .ending:
      settleForConversation(snapshot)
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

  private func beginCrossDisplayRelocation() {
    relocationGeneration &+= 1
    let generation = relocationGeneration
    isRelocating = true
    relocationPositionedPlacement = nil
    stopMotion()
    panel.stopPointerTracking()

    animationDriver.fade(
      panel,
      to: 0,
      duration: Self.relocationFadePhaseDuration
    ) { [weak self] in
      guard
        let self,
        self.relocationGeneration == generation,
        let snapshot = self.latestSnapshot,
        snapshot.isVisible
      else {
        return
      }

      self.characterCenter = snapshot.placement.position
      self.relocationPositionedPlacement = snapshot.placement
      self.positionPanel()
      self.beginRelocationFadeIn(generation: generation)
    }
  }

  private func beginRelocationFadeIn(generation: Int) {
    animationDriver.fade(
      panel,
      to: 1,
      duration: Self.relocationFadePhaseDuration
    ) { [weak self] in
      guard
        let self,
        self.relocationGeneration == generation
      else {
        return
      }
      self.isRelocating = false
      self.relocationPositionedPlacement = nil
      guard let snapshot = self.latestSnapshot else {
        return
      }
      Task { @MainActor [weak self] in
        await self?.render(snapshot)
      }
    }
  }

  private func settleForConversation(_ snapshot: CompanionSnapshot) {
    characterCenter = clampToSurface(
      characterCenter,
      surface: terrain.surface(for: snapshot.placement),
      horizontalInset: Self.canvasSize.width / 2
    )
  }

  private func startRoamingIfNeeded(avatarChanged: Bool) {
    guard currentMotionPlan == nil else {
      if avatarChanged {
        beginRoamingPlan()
      }
      return
    }

    if holdRemaining > 0 {
      if avatarChanged {
        quietHoldAnimationState = AnimationStateID("front-neutral")
      }
      showAnimation(
        named: quietHoldAnimationState.rawValue,
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
    let intent = roamingIntentSelector.nextIntent(
      for: snapshot.avatar,
      at: characterCenter,
      within: surface
    )
    prepareCharacterCenter(
      for: intent,
      avatar: snapshot.avatar,
      surface: surface
    )
    guard
      let plan = try? motionPlanner.plan(
        intent,
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

    var remaining = elapsed
    while remaining > Self.clockEpsilon {
      if holdRemaining > Self.clockEpsilon {
        let consumed = min(remaining, holdRemaining)
        holdRemaining -= consumed
        remaining -= consumed
        if holdRemaining <= Self.clockEpsilon {
          holdRemaining = 0
          beginRoamingPlan()
        }
        continue
      }

      guard
        let plan = currentMotionPlan,
        plan.steps.indices.contains(activeStepIndex)
      else {
        beginRoamingPlan()
        if currentMotionPlan == nil {
          break
        }
        continue
      }

      let step = plan.steps[activeStepIndex]
      let stepDuration = roamingDuration(
        for: step,
        in: plan,
        avatar: snapshot.avatar
      )
      let stepRemaining = max(0, stepDuration - animationElapsed)
      let burstRemaining = max(
        0,
        Self.roamingBurstDuration - burstElapsed
      )
      let consumed = min(remaining, stepRemaining, burstRemaining)

      guard consumed > Self.clockEpsilon else {
        finishRoamingPlan()
        continue
      }

      let reachedBoundary = apply(
        step.translation,
        elapsed: consumed,
        snapshot: snapshot
      )
      advanceAnimation(by: consumed)
      burstElapsed += consumed
      remaining -= consumed

      if reachedBoundary
        || burstElapsed + Self.clockEpsilon >= Self.roamingBurstDuration
      {
        finishRoamingPlan()
        continue
      }

      if animationElapsed + Self.clockEpsilon >= stepDuration {
        guard plan.steps.indices.contains(activeStepIndex + 1) else {
          finishRoamingPlan()
          continue
        }
        activeStepIndex += 1
        showAnimation(
          named: plan.steps[activeStepIndex].state.rawValue,
          avatarChanged: false
        )
      }
    }

    positionPanel()
  }

  private func roamingDuration(
    for step: MotionPlanStep,
    in plan: MotionPlan,
    avatar: CompanionAvatar
  ) -> TimeInterval {
    guard
      plan.steps.count == 1,
      manifests[avatar]?.animations[step.state]?.loops == true
    else {
      return step.durationSeconds
    }
    return Self.roamingBurstDuration
  }

  private func finishRoamingPlan() {
    guard let completedPlan = currentMotionPlan else {
      return
    }

    quietHoldAnimationState = quietHoldState(for: completedPlan)
    currentMotionPlan = nil
    activeStepIndex = 0
    animationElapsed = 0
    burstElapsed = 0
    holdRemaining = Self.roamingHoldDuration
    showAnimation(
      named: quietHoldAnimationState.rawValue,
      avatarChanged: false
    )
  }

  private func quietHoldState(
    for completedPlan: MotionPlan
  ) -> AnimationStateID {
    switch (completedPlan.avatar, completedPlan.intent) {
    case (.orion, .climbUp), (.orion, .cling):
      AnimationStateID("wall-cling")
    case (.athena, .takeoff),
      (.athena, .glide),
      (.athena, .hover),
      (.athena, .slowDrift):
      AnimationStateID("hover")
    default:
      AnimationStateID("front-neutral")
    }
  }

  private func apply(
    _ translation: MotionTranslation,
    elapsed: TimeInterval,
    snapshot: CompanionSnapshot
  ) -> Bool {
    var translated = characterCenter

    switch translation {
    case .stationary:
      break
    case .groundedWalk(let direction, let pointsPerSecond),
      .edgeEntry(let direction, let pointsPerSecond):
      let sign = direction == .left ? -1.0 : 1.0
      translated.x += sign * pointsPerSecond * elapsed
    case .vertical(let direction, let pointsPerSecond):
      let sign = direction == .down ? -1.0 : 1.0
      translated.y += sign * pointsPerSecond * elapsed
    case .slowAirborneDrift(let direction, let pointsPerSecond):
      let sign = direction == .left ? -1.0 : 1.0
      translated.x += sign * pointsPerSecond * elapsed
    case .airborneJump(
      let direction,
      let horizontalPointsPerSecond,
      let downwardPointsPerSecond
    ):
      let sign = direction == .left ? -1.0 : 1.0
      translated.x += sign * horizontalPointsPerSecond * elapsed
      translated.y -= downwardPointsPerSecond * elapsed
    }

    let surface = terrain.surface(for: snapshot.placement)
    let horizontalInset =
      usesOrionEdgeBounds ? 0 : Self.canvasSize.width / 2
    let clamped = clampToSurface(
      translated,
      surface: surface,
      horizontalInset: horizontalInset
    )

    characterCenter = clamped
    return clamped != translated
      || reachesSurfaceBoundary(
        translation,
        point: clamped,
        surface: surface,
        horizontalInset: horizontalInset
      )
  }

  private var usesOrionEdgeBounds: Bool {
    guard let intent = currentMotionPlan?.intent else {
      return false
    }
    return usesOrionEdgeBounds(
      for: intent,
      avatar: presentedAvatar
    )
  }

  private func prepareCharacterCenter(
    for intent: MotionIntent,
    avatar: CompanionAvatar,
    surface: CompanionStageSurface
  ) {
    let safeInset = Self.canvasSize.width / 2
    let horizontalInset =
      usesOrionEdgeBounds(for: intent, avatar: avatar)
      ? 0
      : safeInset
    characterCenter = clampToSurface(
      characterCenter,
      surface: surface,
      horizontalInset: horizontalInset
    )

    guard avatar == .orion else {
      return
    }
    switch intent {
    case .cling:
      let distanceFromLeft = abs(
        characterCenter.x - surface.visibleFrame.minX
      )
      let distanceFromRight = abs(
        surface.visibleFrame.maxX - characterCenter.x
      )
      characterCenter.x =
        distanceFromLeft <= distanceFromRight
        ? surface.visibleFrame.minX
        : surface.visibleFrame.maxX
    default:
      break
    }
  }

  private func usesOrionEdgeBounds(
    for intent: MotionIntent,
    avatar: CompanionAvatar
  ) -> Bool {
    guard avatar == .orion else {
      return false
    }
    switch intent {
    case .climbUp, .cling, .jumpDown:
      return true
    default:
      return false
    }
  }

  private func clampToSurface(
    _ point: StagePoint,
    surface: CompanionStageSurface,
    horizontalInset: Double
  ) -> StagePoint {
    let verticalInset = Self.canvasSize.height / 2
    let minimumX = surface.visibleFrame.minX + horizontalInset
    let maximumX = max(
      minimumX,
      surface.visibleFrame.maxX - horizontalInset
    )
    let minimumY = surface.visibleFrame.minY + verticalInset
    let maximumY = max(
      minimumY,
      surface.visibleFrame.maxY - verticalInset
    )

    return StagePoint(
      x: min(max(point.x, minimumX), maximumX),
      y: min(max(point.y, minimumY), maximumY)
    )
  }

  private func reachesSurfaceBoundary(
    _ translation: MotionTranslation,
    point: StagePoint,
    surface: CompanionStageSurface,
    horizontalInset: Double
  ) -> Bool {
    let left = surface.visibleFrame.minX + horizontalInset
    let right = surface.visibleFrame.maxX - horizontalInset
    let bottom = surface.visibleFrame.minY + Self.canvasSize.height / 2
    let top = surface.visibleFrame.maxY - Self.canvasSize.height / 2

    switch translation {
    case .stationary:
      return false
    case .edgeEntry:
      return false
    case .groundedWalk(let direction, _),
      .slowAirborneDrift(let direction, _):
      return direction == .left
        ? abs(point.x - left) <= Self.clockEpsilon
        : abs(point.x - right) <= Self.clockEpsilon
    case .vertical(let direction, _):
      return direction == .down
        ? abs(point.y - bottom) <= Self.clockEpsilon
        : abs(point.y - top) <= Self.clockEpsilon
    case .airborneJump(let direction, _, _):
      let horizontalBoundaryReached =
        direction == .left
        ? abs(point.x - left) <= Self.clockEpsilon
        : abs(point.x - right) <= Self.clockEpsilon
      return horizontalBoundaryReached
        || abs(point.y - bottom) <= Self.clockEpsilon
    }
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

    let previousAnimationState = currentAnimationState
    currentAnimationState = animation.id
    currentFrameURLs = animation.frames
    animationElapsed = 0
    if avatarChanged {
      lastCrossfadeDuration = 0.2
    } else if previousAnimationState != nil,
      previousAnimationState != animation.id
    {
      lastCrossfadeDuration = Self.poseCrossfadeDuration
    } else {
      lastCrossfadeDuration = 0
    }
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
    quietHoldAnimationState = AnimationStateID("front-neutral")
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
  private weak var accessibilityRootView: NSView?
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
    setAccessibilityIdentifier("companion.window")

    let rootView = NSView(frame: contentRect)
    rootView.autoresizingMask = [.width, .height]
    rootView.setAccessibilityElement(true)
    rootView.setAccessibilityRole(.group)
    rootView.setAccessibilityLabel("Desktop companion")
    rootView.setAccessibilityIdentifier("companion.stage")
    accessibilityRootView = rootView

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

  func updateAccessibilityPresentation(
    avatar: CompanionAvatar,
    presence: PresenceState
  ) {
    let avatarName = avatar.rawValue.capitalized
    let presenceName = presence.rawValue.capitalized
    accessibilityRootView?.setAccessibilityValue(
      "\(avatarName), \(presenceName)"
    )
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
