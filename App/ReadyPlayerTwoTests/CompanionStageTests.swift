import AppKit
import CompanionRuntime
import SpriteKit
import Testing

@testable import ReadyPlayerTwo

@Suite(.serialized)
@MainActor
struct CompanionStageTests {
  @Test
  func bothRealAvatarManifestsAreReadyBeforeEitherAvatarCanRender() async throws {
    let bundle = Bundle(for: AppDelegate.self)
    let resourceURL = try #require(bundle.resourceURL)
    let stage = try CompanionStage(
      assetRootURL: resourceURL,
      panelPresentationEnabled: false,
      hostsSpriteView: false
    )

    #expect(stage.availableAvatars == Set(CompanionAvatar.allCases))

    await stage.render(Self.snapshot(avatar: .orion, isVisible: false))
    #expect(stage.presentedAvatar == .orion)

    await stage.render(Self.snapshot(avatar: .athena, isVisible: false))
    #expect(stage.presentedAvatar == .athena)
  }

  @Test
  func visibleCharacterUsesAPixelAlignedTransparentSpriteKitPanel() async throws {
    let bundle = Bundle(for: AppDelegate.self)
    let resourceURL = try #require(bundle.resourceURL)
    let terrain = FixedCompanionStageTerrain(
      surface: CompanionStageSurface(
        visibleFrame: NSRect(x: 0, y: 0, width: 1_280, height: 800),
        scaleFactor: 2
      )
    )
    let stage = try CompanionStage(
      assetRootURL: resourceURL,
      terrain: terrain,
      panelPresentationEnabled: false,
      hostsSpriteView: false
    )

    await stage.render(
      Self.snapshot(
        avatar: .orion,
        isVisible: true,
        position: StagePoint(x: 100.3, y: 200.2)
      )
    )
    defer {
      stage.panel.orderOut(nil)
    }

    #expect(stage.panel.frame.size == CompanionStage.canvasSize)
    #expect(!(stage.panel.contentView is SKView))
    #expect(stage.scene.size == CompanionStage.canvasSize)
    #expect(stage.scene.backgroundColor.alphaComponent == 0)
    #expect(stage.scene.children.count == 1)
    #expect(stage.scene.children.first is SKSpriteNode)
    #expect(stage.panel.frame.origin.x * 2 == 72)
    #expect(stage.panel.frame.origin.y * 2 == 272)
  }

  @Test
  func orionRoamingUsesARealPlannerSequenceAndTravelsFluidly() async throws {
    let bundle = Bundle(for: AppDelegate.self)
    let resourceURL = try #require(bundle.resourceURL)
    let driver = ManualCompanionStageFrameDriver()
    let stage = try CompanionStage(
      assetRootURL: resourceURL,
      terrain: FixedCompanionStageTerrain(
        surface: CompanionStageSurface(
          visibleFrame: NSRect(x: 0, y: 0, width: 1_280, height: 800),
          scaleFactor: 2
        )
      ),
      frameDriver: driver,
      panelPresentationEnabled: false,
      hostsSpriteView: false
    )

    await stage.render(
      Self.snapshot(
        avatar: .orion,
        isVisible: true,
        position: StagePoint(x: 640, y: 400)
      )
    )

    #expect(stage.currentMotionPlan?.states == [AnimationStateID("walk-right")])
    #expect(stage.currentAnimationState == AnimationStateID("walk-right"))
    #expect(stage.currentFrameURLs.count == 8)
    #expect(
      stage.currentFrameURLs.first?.lastPathComponent
        == "warrior-walk-right-01.png"
    )
    #expect(driver.isRunning)

    driver.advance(by: 0.25)

    #expect(stage.characterCenter == StagePoint(x: 652, y: 400))
    #expect(stage.panel.frame.origin == NSPoint(x: 588, y: 336))
  }

  @Test
  func reduceMotionKeepsRoamingStaticAndFullyVisible() async throws {
    let bundle = Bundle(for: AppDelegate.self)
    let resourceURL = try #require(bundle.resourceURL)
    let driver = ManualCompanionStageFrameDriver()
    let stage = try CompanionStage(
      assetRootURL: resourceURL,
      terrain: FixedCompanionStageTerrain(
        surface: CompanionStageSurface(
          visibleFrame: NSRect(x: 0, y: 0, width: 1_280, height: 800),
          scaleFactor: 2
        )
      ),
      frameDriver: driver,
      motionPreference: FixedCompanionStageMotionPreference(
        shouldReduceMotion: true
      ),
      panelPresentationEnabled: false,
      hostsSpriteView: false
    )

    await stage.render(
      Self.snapshot(
        avatar: .athena,
        isVisible: true,
        position: StagePoint(x: 640, y: 400)
      )
    )
    driver.advance(by: 1)

    #expect(stage.currentMotionPlan == nil)
    #expect(stage.currentAnimationState == AnimationStateID("front-neutral"))
    #expect(
      stage.currentFrameURLs.first?.lastPathComponent
        == "angel-front-neutral.png"
    )
    #expect(stage.characterCenter == StagePoint(x: 640, y: 400))
    #expect(!driver.isRunning)
  }

  @Test
  func summonSettlesInPlaceAndAvatarSwitchCrossfades() async throws {
    let bundle = Bundle(for: AppDelegate.self)
    let resourceURL = try #require(bundle.resourceURL)
    let driver = ManualCompanionStageFrameDriver()
    let stage = try CompanionStage(
      assetRootURL: resourceURL,
      terrain: FixedCompanionStageTerrain(
        surface: CompanionStageSurface(
          visibleFrame: NSRect(x: 0, y: 0, width: 1_280, height: 800),
          scaleFactor: 2
        )
      ),
      frameDriver: driver,
      panelPresentationEnabled: false,
      hostsSpriteView: false
    )

    await stage.render(
      Self.snapshot(
        avatar: .orion,
        isVisible: true,
        position: StagePoint(x: 640, y: 400)
      )
    )
    driver.advance(by: 0.25)

    await stage.render(
      Self.snapshot(
        avatar: .athena,
        isVisible: true,
        position: StagePoint(x: 640, y: 400),
        voice: .listening
      )
    )

    #expect(stage.characterCenter == StagePoint(x: 652, y: 400))
    #expect(stage.currentMotionPlan == nil)
    #expect(stage.currentAnimationState == AnimationStateID("front-neutral"))
    #expect(
      stage.currentFrameURLs.first?.lastPathComponent
        == "angel-front-neutral.png"
    )
    #expect(stage.lastCrossfadeDuration == 0.2)
    #expect(!driver.isRunning)
    #expect(stage.panel.collectionBehavior.contains(.fullScreenAuxiliary))

    await stage.render(
      Self.snapshot(
        avatar: .athena,
        isVisible: true,
        position: StagePoint(x: 640, y: 400),
        voice: .speaking
      )
    )

    #expect(stage.currentAnimationState == AnimationStateID("front-happy"))
    #expect(
      stage.currentFrameURLs.first?.lastPathComponent
        == "angel-front-happy.png"
    )
  }

  @Test
  func alphaHitTestingRoutesClickAndDragOnlyThroughCharacterPixels() async throws {
    let bundle = Bundle(for: AppDelegate.self)
    let resourceURL = try #require(bundle.resourceURL)
    let actions = CompanionStageActions()
    var summonCount = 0
    var parkedPoints: [StagePoint] = []
    actions.connect(
      summon: {
        summonCount += 1
      },
      dragToPark: { point in
        parkedPoints.append(point)
      }
    )
    let stage = try CompanionStage(
      assetRootURL: resourceURL,
      terrain: FixedCompanionStageTerrain(
        surface: CompanionStageSurface(
          visibleFrame: NSRect(x: 0, y: 0, width: 1_280, height: 800),
          scaleFactor: 2
        )
      ),
      frameDriver: ManualCompanionStageFrameDriver(),
      actions: actions,
      panelPresentationEnabled: false,
      hostsSpriteView: false
    )

    await stage.render(
      Self.snapshot(
        avatar: .orion,
        isVisible: true,
        position: StagePoint(x: 640, y: 400)
      )
    )

    stage.panel.updateMousePassthrough(
      atScreenPoint: NSPoint(
        x: stage.panel.frame.minX + 2,
        y: stage.panel.frame.maxY - 2
      )
    )
    #expect(stage.panel.ignoresMouseEvents)

    stage.panel.updateMousePassthrough(
      atScreenPoint: NSPoint(
        x: stage.panel.frame.minX + 50,
        y: stage.panel.frame.midY
      )
    )
    #expect(!stage.panel.ignoresMouseEvents)

    stage.panel.performCharacterClick()
    stage.panel.performCharacterDrag(
      to: StagePoint(x: 900, y: 300)
    )
    await drainStageTasks()

    #expect(summonCount == 1)
    #expect(parkedPoints == [StagePoint(x: 900, y: 300)])
    #expect(!stage.panel.canBecomeKey)
    #expect(!stage.panel.canBecomeMain)
  }

  private static func snapshot(
    avatar: CompanionAvatar,
    isVisible: Bool,
    position: StagePoint = StagePoint(x: 640, y: 400),
    voice: VoiceSessionState = .idle
  ) -> CompanionSnapshot {
    CompanionSnapshot(
      avatar: avatar,
      basePresence: isVisible ? .roaming : .hidden,
      isVisible: isVisible,
      placement: CompanionPlacement(
        displayID: "main",
        position: position
      ),
      voice: voice,
      bubble: voice == .idle ? .hidden : .listening,
      waveformEnergy: 0,
      recoverableError: nil
    )
  }
}

@MainActor
private func drainStageTasks() async {
  for _ in 0..<20 {
    await Task.yield()
  }
}

@MainActor
private final class ManualCompanionStageFrameDriver:
  CompanionStageFrameDriving
{
  private var tick: ((TimeInterval) -> Void)?

  var isRunning: Bool {
    tick != nil
  }

  func start(tick: @escaping (TimeInterval) -> Void) {
    self.tick = tick
  }

  func stop() {
    tick = nil
  }

  func advance(by elapsed: TimeInterval) {
    tick?(elapsed)
  }
}

@MainActor
private struct FixedCompanionStageTerrain: CompanionStageTerrain {
  let surface: CompanionStageSurface

  func surface(for _: CompanionPlacement) -> CompanionStageSurface {
    surface
  }
}

@MainActor
private struct FixedCompanionStageMotionPreference:
  CompanionStageMotionPreference
{
  let shouldReduceMotion: Bool
}
