public enum HorizontalDirection: String, Codable, Sendable {
  case left
  case right
}

public enum VerticalDirection: String, Codable, Sendable {
  case up
  case down
}

public enum MotionIntent: Equatable, Sendable {
  case walk(HorizontalDirection)
  case climbUp(entryFrom: HorizontalDirection)
  case cling
  case jumpDown(landingToward: HorizontalDirection)
  case land(HorizontalDirection)
  case takeoff(HorizontalDirection)
  case glide(VerticalDirection)
  case hover
  case slowDrift(HorizontalDirection)
}

public enum MotionTranslation: Equatable, Sendable {
  case stationary
  case groundedWalk(direction: HorizontalDirection, pointsPerSecond: Double)
  case vertical(direction: VerticalDirection, pointsPerSecond: Double)
  case slowAirborneDrift(direction: HorizontalDirection, pointsPerSecond: Double)
}

public struct MotionPlanStep: Equatable, Sendable {
  public let state: AnimationStateID
  public let durationSeconds: Double
  public let translation: MotionTranslation

  public init(
    state: AnimationStateID,
    durationSeconds: Double,
    translation: MotionTranslation
  ) {
    self.state = state
    self.durationSeconds = durationSeconds
    self.translation = translation
  }
}

public struct MotionPlan: Equatable, Sendable {
  public let avatar: CompanionAvatar
  public let intent: MotionIntent
  public let steps: [MotionPlanStep]

  public var states: [AnimationStateID] {
    steps.map(\.state)
  }

  public init(
    avatar: CompanionAvatar,
    intent: MotionIntent,
    steps: [MotionPlanStep]
  ) {
    self.avatar = avatar
    self.intent = intent
    self.steps = steps
  }
}

public enum MotionPlanningError: Error, Equatable, Sendable {
  case unsupportedIntent(avatar: CompanionAvatar, intent: MotionIntent)
  case missingAnimation(avatar: CompanionAvatar, state: AnimationStateID)
  case invalidAnimationDuration(state: AnimationStateID, seconds: Double)
}

public struct MotionPlanner: Sendable {
  public init() {}

  public func plan(
    _ intent: MotionIntent,
    using manifest: AvatarAnimationManifest
  ) throws -> MotionPlan {
    let specifications = try specifications(
      for: intent,
      avatar: manifest.avatar
    )
    let steps = try specifications.map { specification in
      guard let animation = manifest.animations[specification.state] else {
        throw MotionPlanningError.missingAnimation(
          avatar: manifest.avatar,
          state: specification.state
        )
      }
      let duration = animation.durationSeconds
      guard duration.isFinite, duration > 0 else {
        throw MotionPlanningError.invalidAnimationDuration(
          state: specification.state,
          seconds: duration
        )
      }

      return MotionPlanStep(
        state: specification.state,
        durationSeconds: duration,
        translation: specification.translation
      )
    }

    return MotionPlan(
      avatar: manifest.avatar,
      intent: intent,
      steps: steps
    )
  }

  private func specifications(
    for intent: MotionIntent,
    avatar: CompanionAvatar
  ) throws -> [StepSpecification] {
    switch (avatar, intent) {
    case (.orion, .walk(let direction)):
      [
        StepSpecification(
          state: state("walk", direction),
          translation: .groundedWalk(
            direction: direction,
            pointsPerSecond: 48
          )
        )
      ]

    case (.orion, .climbUp(let entryDirection)):
      [
        StepSpecification(
          state: state("climb-entry", entryDirection),
          translation: .stationary
        ),
        StepSpecification(
          state: AnimationStateID("wall-cling"),
          translation: .stationary
        ),
        StepSpecification(
          state: AnimationStateID("climb-up"),
          translation: .vertical(direction: .up, pointsPerSecond: 32)
        ),
      ]

    case (.orion, .cling):
      [
        StepSpecification(
          state: AnimationStateID("wall-cling"),
          translation: .stationary
        )
      ]

    case (.orion, .jumpDown(let landingDirection)):
      [
        StepSpecification(
          state: AnimationStateID("jump-down"),
          translation: .vertical(direction: .down, pointsPerSecond: 64)
        ),
        StepSpecification(
          state: state("landing", landingDirection),
          translation: .stationary
        ),
      ]

    case (.orion, .land(let direction)):
      [
        StepSpecification(
          state: state("landing", direction),
          translation: .stationary
        ),
        StepSpecification(
          state: state("walk", direction),
          translation: .groundedWalk(
            direction: direction,
            pointsPerSecond: 48
          )
        ),
      ]

    case (.athena, .walk(let direction)):
      [
        StepSpecification(
          state: state("walk", direction),
          translation: .groundedWalk(
            direction: direction,
            pointsPerSecond: 48
          )
        )
      ]

    case (.athena, .takeoff(let direction)):
      [
        StepSpecification(
          state: state("takeoff", direction),
          translation: .vertical(direction: .up, pointsPerSecond: 32)
        ),
        StepSpecification(
          state: AnimationStateID("hover"),
          translation: .stationary
        ),
      ]

    case (.athena, .glide(let direction)):
      [
        StepSpecification(
          state: AnimationStateID("glide-\(direction.rawValue)"),
          translation: .vertical(direction: direction, pointsPerSecond: 36)
        )
      ]

    case (.athena, .hover):
      [
        StepSpecification(
          state: AnimationStateID("hover"),
          translation: .stationary
        )
      ]

    case (.athena, .land(let direction)):
      [
        StepSpecification(
          state: state("landing", direction),
          translation: .vertical(direction: .down, pointsPerSecond: 32)
        ),
        StepSpecification(
          state: state("neutral", direction),
          translation: .stationary
        ),
      ]

    case (.athena, .slowDrift(let direction)):
      [
        StepSpecification(
          state: AnimationStateID("hover"),
          translation: .slowAirborneDrift(
            direction: direction,
            pointsPerSecond: 12
          )
        )
      ]

    default:
      throw MotionPlanningError.unsupportedIntent(
        avatar: avatar,
        intent: intent
      )
    }
  }

  private func state(
    _ capability: String,
    _ direction: HorizontalDirection
  ) -> AnimationStateID {
    if capability == "neutral" {
      return AnimationStateID("\(direction.rawValue)-neutral")
    }
    return AnimationStateID("\(capability)-\(direction.rawValue)")
  }
}

private struct StepSpecification {
  let state: AnimationStateID
  let translation: MotionTranslation
}
