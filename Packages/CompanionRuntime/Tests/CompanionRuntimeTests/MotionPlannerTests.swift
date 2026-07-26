import CompanionRuntime
import Foundation
import Testing

@Suite
struct MotionPlannerTests {
  @Test
  func orionPlansOnlyWalkClimbClingJumpAndLandingStates() throws {
    let manifest = try Self.manifest(
      avatar: .orion,
      directory: "avatar-orion"
    )
    let planner = MotionPlanner()
    let cases: [(MotionIntent, [String])] = [
      (.walk(.left), ["walk-left"]),
      (
        .climbUp(entryFrom: .right),
        ["climb-entry-right", "wall-cling", "climb-up"]
      ),
      (.cling, ["wall-cling"]),
      (.jumpDown(landingToward: .left), ["jump-down", "landing-left"]),
      (.land(.right), ["landing-right", "walk-right"]),
    ]

    for (intent, expectedStates) in cases {
      let plan = try planner.plan(intent, using: manifest)

      #expect(plan.avatar == .orion)
      #expect(plan.intent == intent)
      #expect(plan.states.map(\.rawValue) == expectedStates)
      #expect(plan.steps.allSatisfy { $0.durationSeconds > 0 })
      #expect(plan.states.allSatisfy { manifest.animations[$0] != nil })
      #expect(plan == (try planner.plan(intent, using: manifest)))
    }

    let jump = try planner.plan(
      .jumpDown(landingToward: .left),
      using: manifest
    )
    let climb = try planner.plan(
      .climbUp(entryFrom: .right),
      using: manifest
    )
    #expect(
      climb.steps.first?.translation
        == .edgeEntry(
          direction: .right,
          pointsPerSecond: 160
        )
    )
    #expect(
      jump.steps.map(\.translation)
        == [
          .airborneJump(
            direction: .left,
            horizontalPointsPerSecond: 96,
            downwardPointsPerSecond: 64
          ),
          .stationary,
        ]
    )
  }

  @Test
  func athenaPlansOnlyWalkTakeoffGlideHoverLandAndSlowDriftStates() throws {
    let manifest = try Self.manifest(
      avatar: .athena,
      directory: "avatar-athena"
    )
    let planner = MotionPlanner()
    let cases: [(MotionIntent, [String])] = [
      (.walk(.right), ["walk-right"]),
      (.takeoff(.left), ["takeoff-left", "hover"]),
      (.glide(.up), ["glide-up"]),
      (.glide(.down), ["glide-down"]),
      (.hover, ["hover"]),
      (.land(.right), ["landing-right", "right-neutral"]),
      (.slowDrift(.left), ["hover"]),
    ]

    for (intent, expectedStates) in cases {
      let plan = try planner.plan(intent, using: manifest)

      #expect(plan.avatar == .athena)
      #expect(plan.intent == intent)
      #expect(plan.states.map(\.rawValue) == expectedStates)
      #expect(plan.steps.allSatisfy { $0.durationSeconds > 0 })
      #expect(plan.states.allSatisfy { manifest.animations[$0] != nil })
      #expect(plan == (try planner.plan(intent, using: manifest)))
    }

    let drift = try planner.plan(.slowDrift(.left), using: manifest)
    #expect(
      drift.steps.map(\.translation)
        == [
          .slowAirborneDrift(
            direction: .left,
            pointsPerSecond: 12
          )
        ]
    )
  }

  @Test
  func rejectsCapabilitiesThatWouldInventMotionForEitherAvatar() throws {
    let orion = try Self.manifest(
      avatar: .orion,
      directory: "avatar-orion"
    )
    let athena = try Self.manifest(
      avatar: .athena,
      directory: "avatar-athena"
    )
    let planner = MotionPlanner()

    #expect(
      throws: MotionPlanningError.unsupportedIntent(
        avatar: .orion,
        intent: .glide(.down)
      )
    ) {
      try planner.plan(.glide(.down), using: orion)
    }
    #expect(
      throws: MotionPlanningError.unsupportedIntent(
        avatar: .athena,
        intent: .climbUp(entryFrom: .left)
      )
    ) {
      try planner.plan(.climbUp(entryFrom: .left), using: athena)
    }
    #expect(
      throws: MotionPlanningError.unsupportedIntent(
        avatar: .athena,
        intent: .jumpDown(landingToward: .right)
      )
    ) {
      try planner.plan(.jumpDown(landingToward: .right), using: athena)
    }
  }

  private static func manifest(
    avatar: CompanionAvatar,
    directory: String
  ) throws -> AvatarAnimationManifest {
    try AnimationManifestLoader().load(
      avatar: avatar,
      from: assetsRoot.appending(path: directory, directoryHint: .isDirectory)
    )
  }

  private static var assetsRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "assets", directoryHint: .isDirectory)
  }
}
