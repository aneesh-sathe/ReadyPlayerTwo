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
  func roamingAdvancesEveryPlannedStepThenEntersAQuietHold() async throws {
    let bundle = Bundle(for: AppDelegate.self)
    let resourceURL = try #require(bundle.resourceURL)
    let driver = ManualCompanionStageFrameDriver()
    let selector = ScriptedCompanionStageRoamingIntentSelector(
      intents: [
        .climbUp(entryFrom: .right),
        .walk(.left),
      ]
    )
    let stage = try CompanionStage(
      assetRootURL: resourceURL,
      terrain: FixedCompanionStageTerrain(
        surface: CompanionStageSurface(
          visibleFrame: NSRect(x: 0, y: 0, width: 1_280, height: 800),
          scaleFactor: 2
        )
      ),
      frameDriver: driver,
      roamingIntentSelector: selector,
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

    #expect(
      stage.currentMotionPlan?.states.map(\.rawValue)
        == ["climb-entry-right", "wall-cling", "climb-up"]
    )
    #expect(stage.currentAnimationState == AnimationStateID("climb-entry-right"))

    driver.advance(by: 0.4)
    #expect(stage.currentAnimationState == AnimationStateID("wall-cling"))

    driver.advance(by: 2.0 / 3.0)
    #expect(stage.currentAnimationState == AnimationStateID("climb-up"))

    driver.advance(by: 0.8)
    #expect(stage.currentMotionPlan == nil)
    #expect(stage.currentAnimationState == AnimationStateID("wall-cling"))
    #expect(selector.selectionCount == 1)

    driver.advance(by: 2.9)
    #expect(stage.currentMotionPlan == nil)
    #expect(stage.currentAnimationState == AnimationStateID("wall-cling"))
    #expect(selector.selectionCount == 1)

    driver.advance(by: 0.1)
    #expect(stage.currentMotionPlan?.intent == .walk(.left))
    #expect(selector.selectionCount == 2)
  }

  @Test
  func quietHoldsFollowTheCompletedMotionIntent() async throws {
    let bundle = Bundle(for: AppDelegate.self)
    let resourceURL = try #require(bundle.resourceURL)
    let scenarios: [(CompanionAvatar, [StableHoldExpectation])] = [
      (
        .orion,
        [
          .init(
            intent: .walk(.right),
            completionDuration: 2.4,
            state: "front-neutral"
          ),
          .init(
            intent: .climbUp(entryFrom: .right),
            completionDuration: 0.4 + 2.0 / 3.0 + 0.8,
            state: "wall-cling"
          ),
          .init(
            intent: .cling,
            completionDuration: 2.4,
            state: "wall-cling"
          ),
          .init(
            intent: .jumpDown(landingToward: .left),
            completionDuration: 2.0 / 3.0 + 0.4,
            state: "front-neutral"
          ),
          .init(
            intent: .land(.left),
            completionDuration: 0.4 + 0.8,
            state: "front-neutral"
          ),
        ]
      ),
      (
        .athena,
        [
          .init(
            intent: .walk(.right),
            completionDuration: 2.4,
            state: "front-neutral"
          ),
          .init(
            intent: .takeoff(.right),
            completionDuration: 0.4 + 2.0 / 3.0,
            state: "hover"
          ),
          .init(
            intent: .glide(.up),
            completionDuration: 2.4,
            state: "hover"
          ),
          .init(
            intent: .hover,
            completionDuration: 2.4,
            state: "hover"
          ),
          .init(
            intent: .slowDrift(.left),
            completionDuration: 2.4,
            state: "hover"
          ),
          .init(
            intent: .glide(.down),
            completionDuration: 2.4,
            state: "hover"
          ),
          .init(
            intent: .land(.right),
            completionDuration: 0.4 + 1,
            state: "front-neutral"
          ),
        ]
      ),
    ]

    for (avatar, expectations) in scenarios {
      let driver = ManualCompanionStageFrameDriver()
      let selector = ScriptedCompanionStageRoamingIntentSelector(
        intents: expectations.map(\.intent)
      )
      let stage = try CompanionStage(
        assetRootURL: resourceURL,
        terrain: FixedCompanionStageTerrain(
          surface: CompanionStageSurface(
            visibleFrame: NSRect(x: 0, y: 0, width: 1_280, height: 800),
            scaleFactor: 2
          )
        ),
        frameDriver: driver,
        roamingIntentSelector: selector,
        panelPresentationEnabled: false,
        hostsSpriteView: false
      )

      await stage.render(
        Self.snapshot(
          avatar: avatar,
          isVisible: true,
          position: StagePoint(x: 640, y: 400)
        )
      )

      for (index, expectation) in expectations.enumerated() {
        #expect(stage.currentMotionPlan?.intent == expectation.intent)
        driver.advance(by: expectation.completionDuration)

        #expect(stage.currentMotionPlan == nil)
        #expect(
          stage.currentAnimationState
            == AnimationStateID(expectation.state)
        )

        driver.advance(by: 2.9)
        #expect(stage.currentMotionPlan == nil)
        #expect(
          stage.currentAnimationState
            == AnimationStateID(expectation.state)
        )

        guard expectations.indices.contains(index + 1) else {
          continue
        }
        driver.advance(by: 0.1)
        #expect(
          stage.currentMotionPlan?.intent
            == expectations[index + 1].intent
        )
      }
    }
  }

  @Test
  func motionPoseChangesCrossfadeButUnchangedHoldsDoNot() async throws {
    let bundle = Bundle(for: AppDelegate.self)
    let resourceURL = try #require(bundle.resourceURL)

    let edgeDriver = ManualCompanionStageFrameDriver()
    let edgeStage = try Self.scriptedRoamingStage(
      resourceURL: resourceURL,
      driver: edgeDriver,
      intents: [.climbUp(entryFrom: .right)]
    )
    await edgeStage.render(
      Self.snapshot(
        avatar: .orion,
        isVisible: true,
        position: StagePoint(x: 640, y: 400)
      )
    )
    #expect(edgeStage.lastCrossfadeDuration == 0)

    edgeDriver.advance(by: 0.4)
    #expect(edgeStage.currentAnimationState == AnimationStateID("wall-cling"))
    #expect(edgeStage.lastCrossfadeDuration == 0.15)

    edgeDriver.advance(by: 2.0 / 3.0)
    #expect(edgeStage.currentAnimationState == AnimationStateID("climb-up"))
    #expect(edgeStage.lastCrossfadeDuration == 0.15)

    edgeDriver.advance(by: 0.8)
    #expect(edgeStage.currentAnimationState == AnimationStateID("wall-cling"))
    #expect(edgeStage.lastCrossfadeDuration == 0.15)

    let takeoffDriver = ManualCompanionStageFrameDriver()
    let takeoffStage = try Self.scriptedRoamingStage(
      resourceURL: resourceURL,
      driver: takeoffDriver,
      intents: [.takeoff(.right)]
    )
    await takeoffStage.render(
      Self.snapshot(
        avatar: .athena,
        isVisible: true,
        position: StagePoint(x: 640, y: 400)
      )
    )
    #expect(takeoffStage.lastCrossfadeDuration == 0.2)

    takeoffDriver.advance(by: 0.4)
    #expect(
      takeoffStage.currentAnimationState == AnimationStateID("hover")
    )
    #expect(takeoffStage.lastCrossfadeDuration == 0.15)

    takeoffDriver.advance(by: 2.0 / 3.0)
    #expect(
      takeoffStage.currentAnimationState == AnimationStateID("hover")
    )
    #expect(takeoffStage.lastCrossfadeDuration == 0)

    let glideDriver = ManualCompanionStageFrameDriver()
    let glideStage = try Self.scriptedRoamingStage(
      resourceURL: resourceURL,
      driver: glideDriver,
      intents: [.glide(.up)]
    )
    await glideStage.render(
      Self.snapshot(
        avatar: .athena,
        isVisible: true,
        position: StagePoint(x: 640, y: 400)
      )
    )
    glideDriver.advance(by: 2.4)

    #expect(glideStage.currentAnimationState == AnimationStateID("hover"))
    #expect(glideStage.lastCrossfadeDuration == 0.15)
  }

  @Test
  func oneDisplayTickCarriesAcrossMotionPlanStepsWithoutLosingTravel() async throws {
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
      roamingIntentSelector: ScriptedCompanionStageRoamingIntentSelector(
        intents: [.land(.right)]
      ),
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
    driver.advance(by: 0.6)

    #expect(stage.currentAnimationState == AnimationStateID("walk-right"))
    #expect(abs(stage.characterCenter.x - 649.6) < 0.001)
    #expect(stage.characterCenter.y == 400)
  }

  @Test
  func productionOrionRoamingCompletesItsLegalEdgeSequence() async throws {
    let bundle = Bundle(for: AppDelegate.self)
    let resourceURL = try #require(bundle.resourceURL)
    let driver = ManualCompanionStageFrameDriver()
    let stageSurface = CompanionStageSurface(
      visibleFrame: NSRect(x: 0, y: 0, width: 256, height: 400),
      scaleFactor: 2
    )
    let stage = try CompanionStage(
      assetRootURL: resourceURL,
      terrain: FixedCompanionStageTerrain(
        surface: stageSurface
      ),
      frameDriver: driver,
      panelPresentationEnabled: false,
      hostsSpriteView: false
    )

    await stage.render(
      Self.snapshot(
        avatar: .orion,
        isVisible: true,
        position: StagePoint(x: 128, y: 200)
      )
    )
    #expect(stage.currentMotionPlan?.intent == .walk(.right))

    driver.advance(by: 4.0 / 3.0)
    #expect(stage.characterCenter == StagePoint(x: 192, y: 200))
    #expect(stage.currentMotionPlan == nil)
    #expect(Self.isFullyVisible(stage, within: stageSurface))

    driver.advance(by: 3)
    #expect(
      stage.currentMotionPlan?.intent == .climbUp(entryFrom: .right)
    )
    #expect(stage.characterCenter.x == 192)
    #expect(Self.isFullyVisible(stage, within: stageSurface))

    driver.advance(by: 0.2)
    #expect(stage.characterCenter.x == 224)
    #expect(Self.isCenterWithinVisibleFrame(stage, within: stageSurface))
    driver.advance(by: 0.2)
    #expect(stage.currentAnimationState == AnimationStateID("wall-cling"))
    #expect(stage.characterCenter.x == 256)
    #expect(stage.panel.frame.maxX > 256)
    #expect(Self.isCenterWithinVisibleFrame(stage, within: stageSurface))
    driver.advance(by: 2.0 / 3.0)
    #expect(stage.currentAnimationState == AnimationStateID("climb-up"))
    #expect(Self.isCenterWithinVisibleFrame(stage, within: stageSurface))
    driver.advance(by: 0.8)
    driver.advance(by: 3)

    #expect(stage.currentMotionPlan?.intent == .cling)
    #expect(stage.currentAnimationState == AnimationStateID("wall-cling"))
    #expect(Self.isCenterWithinVisibleFrame(stage, within: stageSurface))
    driver.advance(by: 2.4)
    driver.advance(by: 3)

    #expect(
      stage.currentMotionPlan?.intent
        == .jumpDown(landingToward: .left)
    )
    #expect(stage.characterCenter.x == 256)
    #expect(!Self.isFullyVisible(stage, within: stageSurface))

    driver.advance(by: 1.0 / 3.0)
    #expect(stage.characterCenter.x == 224)
    #expect(Self.isCenterWithinVisibleFrame(stage, within: stageSurface))
    driver.advance(by: 1.0 / 3.0)
    #expect(stage.currentAnimationState == AnimationStateID("landing-left"))
    #expect(Self.isFullyVisible(stage, within: stageSurface))
    let landingCenter = stage.characterCenter
    driver.advance(by: 0.1)
    #expect(stage.characterCenter == landingCenter)
    driver.advance(by: 0.3)
    driver.advance(by: 3)

    #expect(stage.currentMotionPlan?.intent == .land(.left))
    driver.advance(by: 0.4)
    #expect(stage.currentAnimationState == AnimationStateID("walk-left"))
    #expect(Self.isFullyVisible(stage, within: stageSurface))
    driver.advance(by: 0.8)
    driver.advance(by: 3)

    #expect(stage.currentMotionPlan?.intent == .walk(.left))
    #expect(Self.isFullyVisible(stage, within: stageSurface))
  }

  @Test
  func productionAthenaRoamingCompletesItsLegalAirborneSequence() async throws {
    let bundle = Bundle(for: AppDelegate.self)
    let resourceURL = try #require(bundle.resourceURL)
    let driver = ManualCompanionStageFrameDriver()
    let surface = CompanionStageSurface(
      visibleFrame: NSRect(x: 0, y: 0, width: 1_280, height: 800),
      scaleFactor: 2
    )
    let stage = try CompanionStage(
      assetRootURL: resourceURL,
      terrain: FixedCompanionStageTerrain(surface: surface),
      frameDriver: driver,
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
    #expect(stage.currentMotionPlan?.intent == .walk(.right))
    #expect(Self.isFullyVisible(stage, within: surface))

    driver.advance(by: 2.4)
    driver.advance(by: 3)
    #expect(stage.currentMotionPlan?.intent == .takeoff(.right))
    driver.advance(by: 0.4)
    #expect(stage.currentAnimationState == AnimationStateID("hover"))
    #expect(Self.isFullyVisible(stage, within: surface))
    driver.advance(by: 2.0 / 3.0)
    driver.advance(by: 3)

    #expect(stage.currentMotionPlan?.intent == .glide(.up))
    driver.advance(by: 2.4)
    #expect(Self.isFullyVisible(stage, within: surface))
    driver.advance(by: 3)

    #expect(stage.currentMotionPlan?.intent == .hover)
    driver.advance(by: 2.4)
    #expect(Self.isFullyVisible(stage, within: surface))
    driver.advance(by: 3)

    #expect(stage.currentMotionPlan?.intent == .slowDrift(.left))
    #expect(
      stage.currentMotionPlan?.steps.map(\.translation)
        == [
          .slowAirborneDrift(
            direction: .left,
            pointsPerSecond: 12
          )
        ]
    )
    driver.advance(by: 2.4)
    #expect(Self.isFullyVisible(stage, within: surface))
    driver.advance(by: 3)

    #expect(stage.currentMotionPlan?.intent == .glide(.down))
    driver.advance(by: 2.4)
    #expect(Self.isFullyVisible(stage, within: surface))
    driver.advance(by: 3)

    #expect(stage.currentMotionPlan?.intent == .land(.right))
    driver.advance(by: 0.4)
    #expect(stage.currentAnimationState == AnimationStateID("right-neutral"))
    #expect(Self.isFullyVisible(stage, within: surface))
    driver.advance(by: 1)
    driver.advance(by: 3)

    #expect(stage.currentMotionPlan?.intent == .walk(.left))
    #expect(Self.isFullyVisible(stage, within: surface))
  }

  @Test
  func conversationInterruptsAnEdgeClimbAtAReachableStablePosition() async throws {
    let bundle = Bundle(for: AppDelegate.self)
    let resourceURL = try #require(bundle.resourceURL)
    let driver = ManualCompanionStageFrameDriver()
    let surface = CompanionStageSurface(
      visibleFrame: NSRect(x: 0, y: 0, width: 1_280, height: 800),
      scaleFactor: 2
    )
    let stage = try CompanionStage(
      assetRootURL: resourceURL,
      terrain: FixedCompanionStageTerrain(surface: surface),
      frameDriver: driver,
      roamingIntentSelector: ScriptedCompanionStageRoamingIntentSelector(
        intents: [
          .climbUp(entryFrom: .right),
          .walk(.left),
        ]
      ),
      panelPresentationEnabled: false,
      hostsSpriteView: false
    )

    await stage.render(
      Self.snapshot(
        avatar: .orion,
        isVisible: true,
        position: StagePoint(x: 1_216, y: 400)
      )
    )
    driver.advance(by: 0.4)
    #expect(stage.currentAnimationState == AnimationStateID("wall-cling"))
    #expect(!Self.isFullyVisible(stage, within: surface))

    await stage.render(
      Self.snapshot(
        avatar: .orion,
        isVisible: true,
        position: StagePoint(x: 1_216, y: 400),
        voice: .listening
      )
    )

    #expect(stage.currentMotionPlan == nil)
    #expect(stage.currentAnimationState == AnimationStateID("front-neutral"))
    #expect(Self.isFullyVisible(stage, within: surface))
    #expect(!driver.isRunning)
    let settledCenter = stage.characterCenter

    driver.advance(by: 30)
    #expect(stage.characterCenter == settledCenter)
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
    #expect(stage.lastCrossfadeDuration == 0.2)

    await stage.render(
      Self.snapshot(
        avatar: .athena,
        isVisible: true,
        position: StagePoint(x: 640, y: 400)
      )
    )
    #expect(stage.lastCrossfadeDuration == 0)
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
  func crossDisplayRelocationFadesOnePanelWithoutSnapping() async throws {
    let bundle = Bundle(for: AppDelegate.self)
    let resourceURL = try #require(bundle.resourceURL)
    let animationDriver = ManualCompanionStageAnimationDriver()
    let stage = try Self.relocationStage(
      resourceURL: resourceURL,
      animationDriver: animationDriver
    )

    await stage.render(
      Self.snapshot(
        avatar: .orion,
        isVisible: true,
        displayID: "built-in",
        position: StagePoint(x: 200, y: 300)
      )
    )
    let originalPanel = stage.panel
    let originalOrigin = NSPoint(x: 136, y: 236)
    #expect(originalPanel.frame.origin == originalOrigin)

    await stage.render(
      Self.snapshot(
        avatar: .orion,
        isVisible: true,
        displayID: "external",
        position: StagePoint(x: -800, y: 500),
        voice: .listening
      )
    )

    #expect(stage.panel === originalPanel)
    #expect(stage.panel.frame.origin == originalOrigin)
    #expect(stage.characterCenter == StagePoint(x: 200, y: 300))
    #expect(stage.panel.alphaValue == 1)
    #expect(animationDriver.requestedDurations == [0.1])

    animationDriver.completeNextAnimation()

    #expect(stage.panel === originalPanel)
    #expect(stage.panel.alphaValue == 0)
    #expect(stage.characterCenter == StagePoint(x: -800, y: 500))
    #expect(stage.panel.frame.origin == NSPoint(x: -864, y: 436))
    #expect(animationDriver.requestedDurations == [0.1, 0.1])

    animationDriver.completeNextAnimation()

    #expect(stage.panel === originalPanel)
    #expect(stage.panel.alphaValue == 1)
    #expect(stage.panel.frame.origin == NSPoint(x: -864, y: 436))
  }

  @Test
  func firstLaunchAndSameDisplayDragStayImmediate() async throws {
    let bundle = Bundle(for: AppDelegate.self)
    let resourceURL = try #require(bundle.resourceURL)
    let animationDriver = ManualCompanionStageAnimationDriver()
    let stage = try Self.relocationStage(
      resourceURL: resourceURL,
      animationDriver: animationDriver
    )

    await stage.render(
      Self.snapshot(
        avatar: .orion,
        isVisible: true,
        displayID: "built-in",
        position: StagePoint(x: 200, y: 300),
        voice: .listening
      )
    )

    #expect(stage.characterCenter == StagePoint(x: 200, y: 300))
    #expect(stage.panel.frame.origin == NSPoint(x: 136, y: 236))
    #expect(animationDriver.requestedDurations.isEmpty)

    await stage.render(
      Self.snapshot(
        avatar: .orion,
        isVisible: true,
        displayID: "built-in",
        position: StagePoint(x: 500, y: 450),
        presence: .parked
      )
    )

    #expect(stage.characterCenter == StagePoint(x: 500, y: 450))
    #expect(stage.panel.frame.origin == NSPoint(x: 436, y: 386))
    #expect(stage.panel.alphaValue == 1)
    #expect(animationDriver.requestedDurations.isEmpty)
  }

  @Test
  func hideDuringRelocationCannotLeaveTheNextShowTransparent() async throws {
    let bundle = Bundle(for: AppDelegate.self)
    let resourceURL = try #require(bundle.resourceURL)
    let animationDriver = ManualCompanionStageAnimationDriver()
    let stage = try Self.relocationStage(
      resourceURL: resourceURL,
      animationDriver: animationDriver
    )

    await stage.render(
      Self.snapshot(
        avatar: .orion,
        isVisible: true,
        displayID: "built-in",
        position: StagePoint(x: 200, y: 300)
      )
    )
    await stage.render(
      Self.snapshot(
        avatar: .orion,
        isVisible: true,
        displayID: "external",
        position: StagePoint(x: -800, y: 500)
      )
    )
    #expect(animationDriver.requestedDurations == [0.1])

    await stage.render(
      Self.snapshot(
        avatar: .orion,
        isVisible: false,
        displayID: "external",
        position: StagePoint(x: -800, y: 500)
      )
    )
    await stage.render(
      Self.snapshot(
        avatar: .orion,
        isVisible: true,
        displayID: "external",
        position: StagePoint(x: -760, y: 460),
        presence: .parked
      )
    )

    #expect(stage.panel.alphaValue == 1)
    #expect(stage.characterCenter == StagePoint(x: -760, y: 460))
    #expect(stage.panel.frame.origin == NSPoint(x: -824, y: 396))

    animationDriver.completeNextAnimation()

    #expect(stage.panel.alphaValue == 1)
    #expect(stage.characterCenter == StagePoint(x: -760, y: 460))
    #expect(stage.panel.frame.origin == NSPoint(x: -824, y: 396))
  }

  @Test
  func relocationFinishesAtTheLatestCrossDisplayDestination() async throws {
    let bundle = Bundle(for: AppDelegate.self)
    let resourceURL = try #require(bundle.resourceURL)
    let animationDriver = ManualCompanionStageAnimationDriver()
    let stage = try Self.relocationStage(
      resourceURL: resourceURL,
      animationDriver: animationDriver
    )

    await stage.render(
      Self.snapshot(
        avatar: .orion,
        isVisible: true,
        displayID: "built-in",
        position: StagePoint(x: 200, y: 300)
      )
    )
    await stage.render(
      Self.snapshot(
        avatar: .orion,
        isVisible: true,
        displayID: "external",
        position: StagePoint(x: -800, y: 500)
      )
    )
    animationDriver.completeNextAnimation()
    #expect(stage.panel.alphaValue == 0)
    #expect(stage.characterCenter == StagePoint(x: -800, y: 500))

    await stage.render(
      Self.snapshot(
        avatar: .orion,
        isVisible: true,
        displayID: "third",
        position: StagePoint(x: 600, y: 500),
        presence: .parked
      )
    )
    #expect(stage.panel.alphaValue == 0)
    #expect(stage.characterCenter == StagePoint(x: 600, y: 500))
    #expect(stage.panel.frame.origin == NSPoint(x: 536, y: 436))

    animationDriver.completeNextAnimation()

    #expect(stage.panel.alphaValue == 1)
    #expect(stage.characterCenter == StagePoint(x: 600, y: 500))
    #expect(stage.panel.frame.origin == NSPoint(x: 536, y: 436))

    await drainStageTasks()

    #expect(stage.panel.alphaValue == 1)
    #expect(stage.characterCenter == StagePoint(x: 600, y: 500))
    #expect(stage.panel.frame.origin == NSPoint(x: 536, y: 436))
  }

  @Test
  func appKitFadeCancellationKeepsTheReplacementAlpha() async throws {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 128, height: 128),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    let animationDriver = AppKitCompanionStageAnimationDriver()
    panel.alphaValue = 1

    animationDriver.fade(
      panel,
      to: 0,
      duration: 0.02
    ) {}
    animationDriver.cancelFades(for: panel)
    panel.alphaValue = 1

    try await Task.sleep(for: .milliseconds(100))

    #expect(panel.alphaValue == 1)
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

  private static func relocationStage(
    resourceURL: URL,
    animationDriver: any CompanionStageAnimationDriving
  ) throws -> CompanionStage {
    try CompanionStage(
      assetRootURL: resourceURL,
      terrain: FixedCompanionStageTerrain(
        surface: CompanionStageSurface(
          visibleFrame: NSRect(
            x: -1_280,
            y: 0,
            width: 2_560,
            height: 800
          ),
          scaleFactor: 2
        )
      ),
      frameDriver: ManualCompanionStageFrameDriver(),
      animationDriver: animationDriver,
      motionPreference: FixedCompanionStageMotionPreference(
        shouldReduceMotion: true
      ),
      panelPresentationEnabled: false,
      hostsSpriteView: false
    )
  }

  private static func scriptedRoamingStage(
    resourceURL: URL,
    driver: ManualCompanionStageFrameDriver,
    intents: [MotionIntent]
  ) throws -> CompanionStage {
    try CompanionStage(
      assetRootURL: resourceURL,
      terrain: FixedCompanionStageTerrain(
        surface: CompanionStageSurface(
          visibleFrame: NSRect(x: 0, y: 0, width: 1_280, height: 800),
          scaleFactor: 2
        )
      ),
      frameDriver: driver,
      roamingIntentSelector: ScriptedCompanionStageRoamingIntentSelector(
        intents: intents
      ),
      panelPresentationEnabled: false,
      hostsSpriteView: false
    )
  }

  private static func snapshot(
    avatar: CompanionAvatar,
    isVisible: Bool,
    displayID: String = "main",
    position: StagePoint = StagePoint(x: 640, y: 400),
    presence: PresenceState? = nil,
    voice: VoiceSessionState = .idle
  ) -> CompanionSnapshot {
    CompanionSnapshot(
      avatar: avatar,
      basePresence: presence ?? (isVisible ? .roaming : .hidden),
      isVisible: isVisible,
      placement: CompanionPlacement(
        displayID: displayID,
        position: position
      ),
      voice: voice,
      bubble: voice == .idle ? .hidden : .listening,
      waveformEnergy: 0,
      recoverableError: nil
    )
  }

  private static func isFullyVisible(
    _ stage: CompanionStage,
    within surface: CompanionStageSurface
  ) -> Bool {
    let inset = CompanionStage.canvasSize.width / 2
    return stage.characterCenter.x >= surface.visibleFrame.minX + inset
      && stage.characterCenter.x <= surface.visibleFrame.maxX - inset
      && stage.characterCenter.y >= surface.visibleFrame.minY + inset
      && stage.characterCenter.y <= surface.visibleFrame.maxY - inset
  }

  private static func isCenterWithinVisibleFrame(
    _ stage: CompanionStage,
    within surface: CompanionStageSurface
  ) -> Bool {
    stage.characterCenter.x >= surface.visibleFrame.minX
      && stage.characterCenter.x <= surface.visibleFrame.maxX
      && stage.characterCenter.y >= surface.visibleFrame.minY
      && stage.characterCenter.y <= surface.visibleFrame.maxY
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
private final class ManualCompanionStageAnimationDriver:
  CompanionStageAnimationDriving
{
  private struct Request {
    weak var panel: NSPanel?
    let alphaValue: CGFloat
    let completion: @MainActor () -> Void
  }

  private var requests: [Request] = []
  private(set) var requestedDurations: [TimeInterval] = []

  func fade(
    _ panel: NSPanel,
    to alphaValue: CGFloat,
    duration: TimeInterval,
    completion: @escaping @MainActor () -> Void
  ) {
    requestedDurations.append(duration)
    requests.append(
      Request(
        panel: panel,
        alphaValue: alphaValue,
        completion: completion
      )
    )
  }

  func cancelFades(for panel: NSPanel) {
    requests.removeAll(where: { $0.panel === panel })
  }

  func completeNextAnimation() {
    guard !requests.isEmpty else {
      return
    }
    let request = requests.removeFirst()
    request.panel?.alphaValue = request.alphaValue
    request.completion()
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

@MainActor
private final class ScriptedCompanionStageRoamingIntentSelector:
  CompanionStageRoamingIntentSelecting
{
  private let intents: [MotionIntent]
  private(set) var selectionCount = 0

  init(intents: [MotionIntent]) {
    self.intents = intents
  }

  func nextIntent(
    for _: CompanionAvatar,
    at _: StagePoint,
    within _: CompanionStageSurface
  ) -> MotionIntent {
    let index = min(selectionCount, intents.count - 1)
    selectionCount += 1
    return intents[index]
  }
}

private struct StableHoldExpectation {
  let intent: MotionIntent
  let completionDuration: TimeInterval
  let state: String
}
