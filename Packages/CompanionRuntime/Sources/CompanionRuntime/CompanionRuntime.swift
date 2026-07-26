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

public enum PlatformEvent: Equatable, Sendable {
  case sleep
  case wake
  case lock
  case unlock
  case screenSaverStarted
  case screenSaverEnded
  case missionControlStarted
  case missionControlEnded
  case displayConfigurationChanged
}

public enum CompanionCommand: Equatable, Sendable {
  case launch
  case summon(SummonSource)
  case endConversation
  case setPresence(PresenceState)
  case selectAvatar(CompanionAvatar)
  case retryConversation
  case drag(to: StagePoint)
  case moveToCurrentDisplay
  case platform(PlatformEvent)
  case setMuted(Bool)
}

public enum VoiceSessionEvent: Equatable, Sendable {
  case listening
  case thinking
  case speaking
  case muted
  case audioEnergy(Double)
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

  public func clamped(_ point: StagePoint, inset: Double = 0) -> StagePoint {
    let minimumX = origin.x + inset
    let minimumY = origin.y + inset
    let maximumX = max(minimumX, origin.x + size.width - inset)
    let maximumY = max(minimumY, origin.y + size.height - inset)

    return StagePoint(
      x: min(max(point.x, minimumX), maximumX),
      y: min(max(point.y, minimumY), maximumY)
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
  public let waveformEnergy: Double
  public let recoverableError: CompanionFailure?

  public init(
    avatar: CompanionAvatar,
    basePresence: PresenceState,
    isVisible: Bool,
    placement: CompanionPlacement,
    voice: VoiceSessionState,
    bubble: BubbleState,
    waveformEnergy: Double,
    recoverableError: CompanionFailure?
  ) {
    self.avatar = avatar
    self.basePresence = basePresence
    self.isVisible = isVisible
    self.placement = placement
    self.voice = voice
    self.bubble = bubble
    self.waveformEnergy = waveformEnergy
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

  private static let firstSpeechDeadline = Duration.seconds(60)
  private static let ongoingSpeechDeadline = Duration.seconds(120)

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
  private var currentDisplay = CompanionDisplay.main
  private var voiceState = VoiceSessionState.idle
  private var bubbleState = BubbleState.hidden
  private var waveformEnergy = 0.0
  private var voiceStateBeforeMute = VoiceSessionState.listening
  private var recoverableError: CompanionFailure?
  private var stageSuppressed = false
  private var voiceEventTask: Task<Void, Never>?
  private var inactivityTask: Task<Void, Never>?
  private var inactivityGeneration = 0
  private var voiceStartGeneration = 0

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

  deinit {
    inactivityTask?.cancel()
    voiceEventTask?.cancel()
  }

  public func send(_ command: CompanionCommand) async {
    switch command {
    case .launch:
      observeVoiceEventsIfNeeded()
      let display = await platform.displayContainingPointer()
      currentDisplay = display
      placement = CompanionPlacement(
        displayID: display.id,
        position: display.visibleFrame.midpoint
      )
      await publish()

    case .summon:
      guard !stageSuppressed else {
        return
      }

      await relocateToPointerDisplayIfNeeded()
      guard voiceState == .idle else {
        await publish()
        return
      }

      await startVoiceSession()

    case .endConversation:
      await endActiveConversation()

    case .setPresence(let presence):
      basePresence = presence

      if presence == .hidden, voiceState != .idle, voiceState != .ending {
        await endActiveConversation()
      } else {
        await publish()
      }

    case .selectAvatar(let selectedAvatar):
      avatar = selectedAvatar
      await publish()

    case .retryConversation:
      guard case .error = voiceState else {
        return
      }

      await startVoiceSession()

    case .drag(let position):
      basePresence = .parked
      placement = CompanionPlacement(
        displayID: currentDisplay.id,
        position: currentDisplay.visibleFrame.clamped(position, inset: 64)
      )
      await publish()

    case .moveToCurrentDisplay:
      let display = await platform.displayContainingPointer()
      currentDisplay = display
      placement = CompanionPlacement(
        displayID: display.id,
        position: display.visibleFrame.midpoint
      )
      await publish()

    case .platform(let event):
      await handlePlatformEvent(event)

    case .setMuted(let isMuted):
      await setMuted(isMuted)
    }
  }

  private func setMuted(_ isMuted: Bool) async {
    if isMuted {
      guard voiceState != .idle, voiceState != .muted, voiceState != .ending else {
        return
      }

      voiceStateBeforeMute = voiceState
      await voice.setMuted(true)
      voiceState = .muted
      bubbleState = .muted
      waveformEnergy = 0
      await publish()
    } else {
      guard voiceState == .muted else {
        return
      }

      await voice.setMuted(false)
      voiceState = voiceStateBeforeMute
      bubbleState = bubble(for: voiceStateBeforeMute)
      waveformEnergy = 0
      await publish()
    }
  }

  private func relocateToPointerDisplayIfNeeded() async {
    let display = await platform.displayContainingPointer()
    guard display.id != currentDisplay.id else {
      return
    }

    currentDisplay = display
    placement = CompanionPlacement(
      displayID: display.id,
      position: display.visibleFrame.midpoint
    )
  }

  private func handlePlatformEvent(_ event: PlatformEvent) async {
    switch event {
    case .sleep, .lock, .screenSaverStarted, .missionControlStarted:
      stageSuppressed = true

      if voiceState != .idle, voiceState != .ending {
        await endActiveConversation()
      } else {
        await publish()
      }

    case .wake, .unlock, .screenSaverEnded, .missionControlEnded:
      stageSuppressed = false
      await publish()

    case .displayConfigurationChanged:
      let display = await platform.displayContainingPointer()
      currentDisplay = display
      placement = CompanionPlacement(
        displayID: display.id,
        position: display.visibleFrame.clamped(
          placement.position,
          inset: 64
        )
      )
      await publish()
    }
  }

  private func startVoiceSession() async {
    cancelInactivityDeadline()
    voiceStartGeneration &+= 1
    let startGeneration = voiceStartGeneration
    observeVoiceEventsIfNeeded()
    voiceState = .connecting
    bubbleState = .connecting
    waveformEnergy = 0
    recoverableError = nil
    scheduleInactivityDeadline(after: Self.firstSpeechDeadline)
    await publish()

    do {
      try await voice.start()
    } catch {
      guard
        voiceStartGeneration == startGeneration,
        acceptsActiveVoiceEvents
      else {
        return
      }

      invalidateVoiceStartAttempt()
      cancelInactivityDeadline()
      let failure =
        (error as? CompanionFailure)
        ?? CompanionFailure(
          kind: .unknown,
          message: "Voice could not start."
        )
      voiceState = .error(failure)
      bubbleState = .error(failure.message)
      waveformEnergy = 0
      recoverableError = failure
      await voice.stop()
      await publish()
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
      guard acceptsActiveVoiceEvents else {
        return
      }
      voiceState = .listening
      bubbleState = .listening
      waveformEnergy = 0
    case .thinking:
      guard acceptsActiveVoiceEvents else {
        return
      }
      scheduleInactivityDeadline(after: Self.ongoingSpeechDeadline)
      voiceState = .thinking
      bubbleState = .thinking
      waveformEnergy = 0
    case .speaking:
      guard acceptsActiveVoiceEvents else {
        return
      }
      voiceState = .speaking
      bubbleState = .speaking
      waveformEnergy = 0
    case .muted:
      guard acceptsActiveVoiceEvents else {
        return
      }
      voiceState = .muted
      bubbleState = .muted
      waveformEnergy = 0
    case .audioEnergy(let energy):
      guard acceptsActiveVoiceEvents else {
        return
      }
      if voiceState == .listening || voiceState == .speaking {
        waveformEnergy = min(max(energy, 0), 1)
      } else {
        waveformEnergy = 0
      }
    case .ended:
      invalidateVoiceStartAttempt()
      cancelInactivityDeadline()
      if case .error = voiceState {
        return
      }
      voiceState = .idle
      bubbleState = .hidden
      waveformEnergy = 0
      recoverableError = nil
    case .failed(let failure):
      guard voiceState != .idle, voiceState != .ending else {
        return
      }
      if case .error = voiceState {
        return
      }
      invalidateVoiceStartAttempt()
      cancelInactivityDeadline()
      voiceState = .error(failure)
      bubbleState = .error(failure.message)
      waveformEnergy = 0
      recoverableError = failure
      await voice.stop()
    }

    await publish()
  }

  private var acceptsActiveVoiceEvents: Bool {
    switch voiceState {
    case .connecting, .listening, .thinking, .speaking, .muted:
      true
    case .idle, .error, .ending:
      false
    }
  }

  private func scheduleInactivityDeadline(after duration: Duration) {
    inactivityGeneration &+= 1
    let generation = inactivityGeneration
    inactivityTask?.cancel()
    let clock = self.clock

    inactivityTask = Task { @MainActor [weak self] in
      do {
        try await clock.sleep(for: duration)
      } catch {
        return
      }

      guard
        let self,
        inactivityGeneration == generation,
        acceptsActiveVoiceEvents
      else {
        return
      }
      await endActiveConversation()
    }
  }

  private func cancelInactivityDeadline() {
    inactivityGeneration &+= 1
    inactivityTask?.cancel()
    inactivityTask = nil
  }

  private func invalidateVoiceStartAttempt() {
    voiceStartGeneration &+= 1
  }

  private func endActiveConversation() async {
    if case .error = voiceState {
      await dismissRecoverableError()
      return
    }
    guard voiceState != .idle, voiceState != .ending else {
      return
    }

    invalidateVoiceStartAttempt()
    cancelInactivityDeadline()
    voiceState = .ending
    bubbleState = .ending
    waveformEnergy = 0
    await publish()
    await voice.stop()
  }

  private func dismissRecoverableError() async {
    invalidateVoiceStartAttempt()
    cancelInactivityDeadline()
    voiceState = .idle
    bubbleState = .hidden
    waveformEnergy = 0
    recoverableError = nil
    await publish()
  }

  private func bubble(for voiceState: VoiceSessionState) -> BubbleState {
    switch voiceState {
    case .idle:
      .hidden
    case .connecting:
      .connecting
    case .listening:
      .listening
    case .thinking:
      .thinking
    case .speaking:
      .speaking
    case .muted:
      .muted
    case .error(let failure):
      .error(failure.message)
    case .ending:
      .ending
    }
  }

  private func publish() async {
    _ = clock
    _ = randomness

    let snapshot = CompanionSnapshot(
      avatar: avatar,
      basePresence: basePresence,
      isVisible: !stageSuppressed && (basePresence != .hidden || voiceState != .idle),
      placement: placement,
      voice: voiceState,
      bubble: bubbleState,
      waveformEnergy: waveformEnergy,
      recoverableError: recoverableError
    )
    snapshotContinuation.yield(snapshot)
    await stage.render(snapshot)
  }
}
