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

  private static func snapshot(
    avatar: CompanionAvatar,
    isVisible: Bool,
    position: StagePoint = StagePoint(x: 640, y: 400)
  ) -> CompanionSnapshot {
    CompanionSnapshot(
      avatar: avatar,
      basePresence: isVisible ? .roaming : .hidden,
      isVisible: isVisible,
      placement: CompanionPlacement(
        displayID: "main",
        position: position
      ),
      voice: .idle,
      bubble: .hidden,
      waveformEnergy: 0,
      recoverableError: nil
    )
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
