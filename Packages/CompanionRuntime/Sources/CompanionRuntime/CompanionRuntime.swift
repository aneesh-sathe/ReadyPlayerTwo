public enum CompanionAvatar: String, CaseIterable, Codable, Sendable {
  case orion
  case athena
}

public enum PresenceState: String, CaseIterable, Codable, Sendable {
  case roaming
  case parked
  case hidden
}

public struct CompanionPreferences: Equatable, Sendable {
  public var avatar: CompanionAvatar
  public var presence: PresenceState

  public init(
    avatar: CompanionAvatar = .orion,
    presence: PresenceState = .roaming
  ) {
    self.avatar = avatar
    self.presence = presence
  }
}

public enum SummonSource: String, Equatable, Sendable {
  case character
  case keyboardShortcut
  case statusMenu
}

public enum CompanionCommand: Equatable, Sendable {
  case launch
  case summon(SummonSource)
  case endConversation
  case setPresence(PresenceState)
}

public enum VoiceSessionEvent: Equatable, Sendable {
  case listening
  case thinking
  case speaking
  case muted
  case ended
  case failed(CompanionFailure)
}

public enum VoiceSessionState: Equatable, Sendable {
  case idle
  case connecting
  case listening
  case thinking
  case speaking
  case muted
  case error(CompanionFailure)
  case ending
}

public enum BubbleState: Equatable, Sendable {
  case hidden
  case connecting
  case listening
  case thinking
  case speaking
  case muted
  case error(String)
  case ending
}

public struct CompanionFailure: Error, Equatable, Sendable {
  public enum Kind: String, Equatable, Sendable {
    case microphoneDenied
    case voiceNotConfigured
    case brokerUnavailable
    case authentication
    case network
    case rateLimited
    case peerConnection
    case audioRoute
    case unknown
  }

  public let kind: Kind
  public let message: String

  public init(kind: Kind, message: String) {
    self.kind = kind
    self.message = message
  }
}

public struct StagePoint: Equatable, Codable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public struct StageSize: Equatable, Codable, Sendable {
  public var width: Double
  public var height: Double

  public init(width: Double, height: Double) {
    self.width = width
    self.height = height
  }
}

public struct StageRect: Equatable, Codable, Sendable {
  public var origin: StagePoint
  public var size: StageSize

  public init(origin: StagePoint, size: StageSize) {
    self.origin = origin
    self.size = size
  }

  public var midpoint: StagePoint {
    StagePoint(
      x: origin.x + size.width / 2,
      y: origin.y + size.height / 2
    )
  }
}

public struct CompanionDisplay: Equatable, Sendable {
  public var id: String
  public var visibleFrame: StageRect
  public var scaleFactor: Double

  public init(
    id: String,
    visibleFrame: StageRect,
    scaleFactor: Double
  ) {
    self.id = id
    self.visibleFrame = visibleFrame
    self.scaleFactor = scaleFactor
  }

  public static let main = CompanionDisplay(
    id: "main",
    visibleFrame: StageRect(
      origin: StagePoint(x: 0, y: 0),
      size: StageSize(width: 1_440, height: 900)
    ),
    scaleFactor: 2
  )
}

public struct CompanionPlacement: Equatable, Sendable {
  public var displayID: String
  public var position: StagePoint

  public init(displayID: String, position: StagePoint) {
    self.displayID = displayID
    self.position = position
  }
}

public struct CompanionSnapshot: Equatable, Sendable {
  public let avatar: CompanionAvatar
  public let basePresence: PresenceState
  public let isVisible: Bool
  public let placement: CompanionPlacement
  public let voice: VoiceSessionState
  public let bubble: BubbleState
  public let recoverableError: CompanionFailure?

  public init(
    avatar: CompanionAvatar,
    basePresence: PresenceState,
    isVisible: Bool,
    placement: CompanionPlacement,
    voice: VoiceSessionState,
    bubble: BubbleState,
    recoverableError: CompanionFailure?
  ) {
    self.avatar = avatar
    self.basePresence = basePresence
    self.isVisible = isVisible
    self.placement = placement
    self.voice = voice
    self.bubble = bubble
    self.recoverableError = recoverableError
  }
}

@MainActor
public protocol StagePort {
  func render(_ snapshot: CompanionSnapshot) async
}

@MainActor
public protocol VoiceSessionPort {
  var events: AsyncStream<VoiceSessionEvent> { get }

  func start() async throws
  func stop() async
  func setMuted(_ isMuted: Bool) async
}

@MainActor
public protocol PlatformPort {
  func displayContainingPointer() async -> CompanionDisplay
}

@MainActor
public protocol RuntimeClock {
  func sleep(for duration: Duration) async throws
}

@MainActor
public protocol RandomSource {
  func nextUnitInterval() -> Double
}

@MainActor
public final class CompanionRuntime {
  public let snapshots: AsyncStream<CompanionSnapshot>

  private let stage: any StagePort
  private let voice: any VoiceSessionPort
  private let platform: any PlatformPort
  private let clock: any RuntimeClock
  private let randomness: any RandomSource
  private let snapshotContinuation: AsyncStream<CompanionSnapshot>.Continuation

  private var avatar: CompanionAvatar
  private var basePresence: PresenceState
  private var placement = CompanionPlacement(
    displayID: CompanionDisplay.main.id,
    position: CompanionDisplay.main.visibleFrame.midpoint
  )
  private var voiceState = VoiceSessionState.idle
  private var bubbleState = BubbleState.hidden
  private var recoverableError: CompanionFailure?
  private var voiceEventTask: Task<Void, Never>?

  public init(
    initialPreferences: CompanionPreferences,
    stage: any StagePort,
    voice: any VoiceSessionPort,
    platform: any PlatformPort,
    clock: any RuntimeClock,
    randomness: any RandomSource
  ) {
    let snapshotStream = AsyncStream<CompanionSnapshot>.makeStream()
    snapshots = snapshotStream.stream
    snapshotContinuation = snapshotStream.continuation
    avatar = initialPreferences.avatar
    basePresence = initialPreferences.presence
    self.stage = stage
    self.voice = voice
    self.platform = platform
    self.clock = clock
    self.randomness = randomness
  }

  public func send(_ command: CompanionCommand) async {
    switch command {
    case .launch:
      observeVoiceEventsIfNeeded()
      let display = await platform.displayContainingPointer()
      placement = CompanionPlacement(
        displayID: display.id,
        position: display.visibleFrame.midpoint
      )
      await publish()

    case .summon:
      guard voiceState == .idle else {
        return
      }

      observeVoiceEventsIfNeeded()
      voiceState = .connecting
      bubbleState = .connecting
      recoverableError = nil
      await publish()

      do {
        try await voice.start()
      } catch {
        let failure =
          (error as? CompanionFailure)
          ?? CompanionFailure(
            kind: .unknown,
            message: "Voice could not start."
          )
        voiceState = .error(failure)
        bubbleState = .error(failure.message)
        recoverableError = failure
        await publish()
      }

    case .endConversation:
      guard voiceState != .idle, voiceState != .ending else {
        return
      }

      voiceState = .ending
      bubbleState = .ending
      await publish()
      await voice.stop()

    case .setPresence(let presence):
      basePresence = presence

      if presence == .hidden, voiceState != .idle, voiceState != .ending {
        voiceState = .ending
        bubbleState = .ending
        await publish()
        await voice.stop()
      } else {
        await publish()
      }
    }
  }

  private func observeVoiceEventsIfNeeded() {
    guard voiceEventTask == nil else {
      return
    }

    let events = voice.events
    voiceEventTask = Task { @MainActor [weak self] in
      for await event in events {
        guard let self else {
          return
        }
        await self.receive(event)
      }
    }
  }

  private func receive(_ event: VoiceSessionEvent) async {
    switch event {
    case .listening:
      voiceState = .listening
      bubbleState = .listening
    case .thinking:
      voiceState = .thinking
      bubbleState = .thinking
    case .speaking:
      voiceState = .speaking
      bubbleState = .speaking
    case .muted:
      voiceState = .muted
      bubbleState = .muted
    case .ended:
      voiceState = .idle
      bubbleState = .hidden
      recoverableError = nil
    case .failed(let failure):
      voiceState = .error(failure)
      bubbleState = .error(failure.message)
      recoverableError = failure
    }

    await publish()
  }

  private func publish() async {
    _ = clock
    _ = randomness

    let snapshot = CompanionSnapshot(
      avatar: avatar,
      basePresence: basePresence,
      isVisible: basePresence != .hidden || voiceState != .idle,
      placement: placement,
      voice: voiceState,
      bubble: bubbleState,
      recoverableError: recoverableError
    )
    snapshotContinuation.yield(snapshot)
    await stage.render(snapshot)
  }
}
