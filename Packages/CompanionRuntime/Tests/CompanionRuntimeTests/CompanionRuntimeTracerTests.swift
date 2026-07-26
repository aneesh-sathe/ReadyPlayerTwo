import CompanionRuntime
import Testing

@Suite(.serialized)
@MainActor
struct CompanionRuntimeTracerTests {
  @Test
  func explicitSummonIsSingletonAndRestoresRoaming() async throws {
    let stage = RecordingStage()
    let voice = ScriptedVoiceSession()
    let clock = ControllableClock()
    let runtime = CompanionRuntime(
      initialPreferences: CompanionPreferences(
        avatar: .orion,
        presence: .roaming
      ),
      stage: stage,
      voice: voice,
      platform: FixedPlatform(),
      clock: clock,
      randomness: FixedRandomSource()
    )
    var snapshots = runtime.snapshots.makeAsyncIterator()

    await runtime.send(.launch)

    let launchValue = await snapshots.next()
    let launched = try #require(launchValue)
    #expect(launched.avatar == .orion)
    #expect(launched.basePresence == .roaming)
    #expect(launched.isVisible)
    #expect(launched.voice == .idle)
    #expect(voice.startCount == 0)

    await runtime.send(.summon(.statusMenu))

    let connectingValue = await snapshots.next()
    let connecting = try #require(connectingValue)
    #expect(connecting.voice == .connecting)
    #expect(voice.startCount == 1)

    voice.emit(.listening)

    let listeningValue = await snapshots.next()
    let listening = try #require(listeningValue)
    #expect(listening.voice == .listening)
    #expect(listening.isVisible)
    await clock.waitForRequestCount(1)

    await runtime.send(.summon(.keyboardShortcut))

    let revealedValue = await snapshots.next()
    let revealed = try #require(revealedValue)
    #expect(revealed.voice == .listening)
    #expect(voice.startCount == 1)

    await runtime.send(.endConversation)

    let endingValue = await snapshots.next()
    let ending = try #require(endingValue)
    #expect(ending.voice == .ending)
    #expect(voice.stopCount == 1)

    voice.emit(.ended)

    let endedValue = await snapshots.next()
    let ended = try #require(endedValue)
    #expect(ended.voice == .idle)
    #expect(ended.basePresence == .roaming)
    #expect(ended.isVisible)

    await clock.advance(by: .seconds(180))
    #expect(voice.startCount == 1)
    #expect(voice.stopCount == 1)
    #expect(clock.cancellationCount == 1)
  }

  @Test
  func presenceControlsStaySilentAndHideEndsConversation() async throws {
    let voice = ScriptedVoiceSession()
    let runtime = CompanionRuntime(
      initialPreferences: CompanionPreferences(),
      stage: RecordingStage(),
      voice: voice,
      platform: FixedPlatform(),
      clock: ControllableClock(),
      randomness: FixedRandomSource()
    )
    var snapshots = runtime.snapshots.makeAsyncIterator()

    await runtime.send(.launch)
    _ = await snapshots.next()

    await runtime.send(.setPresence(.parked))

    let parkedValue = await snapshots.next()
    let parked = try #require(parkedValue)
    #expect(parked.basePresence == .parked)
    #expect(parked.isVisible)
    #expect(voice.startCount == 0)

    await runtime.send(.setPresence(.hidden))

    let hiddenValue = await snapshots.next()
    let hidden = try #require(hiddenValue)
    #expect(hidden.basePresence == .hidden)
    #expect(!hidden.isVisible)
    #expect(voice.startCount == 0)

    await runtime.send(.summon(.character))
    _ = await snapshots.next()
    voice.emit(.listening)
    _ = await snapshots.next()

    await runtime.send(.setPresence(.hidden))

    let endingValue = await snapshots.next()
    let ending = try #require(endingValue)
    #expect(ending.basePresence == .hidden)
    #expect(ending.voice == .ending)
    #expect(ending.isVisible)
    #expect(voice.stopCount == 1)

    voice.emit(.ended)

    let restoredValue = await snapshots.next()
    let restored = try #require(restoredValue)
    #expect(restored.basePresence == .hidden)
    #expect(!restored.isVisible)

    await runtime.send(.setPresence(.roaming))

    let roamingValue = await snapshots.next()
    let roaming = try #require(roamingValue)
    #expect(roaming.basePresence == .roaming)
    #expect(roaming.isVisible)
    #expect(voice.startCount == 1)
  }

  @Test
  func avatarSelectionPreservesTheActiveVoiceSession() async throws {
    let voice = ScriptedVoiceSession()
    let runtime = CompanionRuntime(
      initialPreferences: CompanionPreferences(),
      stage: RecordingStage(),
      voice: voice,
      platform: FixedPlatform(),
      clock: ControllableClock(),
      randomness: FixedRandomSource()
    )
    var snapshots = runtime.snapshots.makeAsyncIterator()

    await runtime.send(.launch)
    _ = await snapshots.next()
    await runtime.send(.summon(.statusMenu))
    _ = await snapshots.next()
    voice.emit(.listening)
    _ = await snapshots.next()

    await runtime.send(.selectAvatar(.athena))

    let athenaValue = await snapshots.next()
    let athena = try #require(athenaValue)
    #expect(athena.avatar == .athena)
    #expect(athena.voice == .listening)
    #expect(voice.startCount == 1)
    #expect(voice.stopCount == 0)

    await runtime.send(.selectAvatar(.orion))

    let orionValue = await snapshots.next()
    let orion = try #require(orionValue)
    #expect(orion.avatar == .orion)
    #expect(orion.voice == .listening)
    #expect(voice.startCount == 1)
    #expect(voice.stopCount == 0)
  }

  @Test
  func voiceFailureStopsCaptureAndRequiresExplicitRetry() async throws {
    let voice = ScriptedVoiceSession()
    let stage = RecordingStage()
    let clock = ControllableClock()
    let runtime = CompanionRuntime(
      initialPreferences: CompanionPreferences(presence: .parked),
      stage: stage,
      voice: voice,
      platform: FixedPlatform(),
      clock: clock,
      randomness: FixedRandomSource()
    )
    var snapshots = runtime.snapshots.makeAsyncIterator()

    await runtime.send(.launch)
    _ = await snapshots.next()
    await runtime.send(.summon(.keyboardShortcut))
    _ = await snapshots.next()
    await clock.waitForRequestCount(1)
    await clock.advance(by: .seconds(30))

    let failure = CompanionFailure(
      kind: .network,
      message: "Connection lost. Retry when ready."
    )
    voice.emit(.failed(failure))

    let failedValue = await snapshots.next()
    let failed = try #require(failedValue)
    #expect(failed.voice == .error(failure))
    #expect(failed.recoverableError == failure)
    #expect(failed.basePresence == .parked)
    #expect(voice.startCount == 1)
    #expect(voice.stopCount == 1)

    await clock.advance(by: .seconds(30))
    #expect(voice.startCount == 1)
    #expect(voice.stopCount == 1)

    voice.emit(.ended)
    await Task.yield()
    await Task.yield()

    let recoveryState = try #require(stage.renderedSnapshots.last)
    #expect(recoveryState.voice == .error(failure))
    #expect(recoveryState.recoverableError == failure)

    await runtime.send(.retryConversation)

    let retryValue = await snapshots.next()
    let retry = try #require(retryValue)
    #expect(retry.voice == .connecting)
    #expect(retry.recoverableError == nil)
    #expect(voice.startCount == 2)
    await clock.waitForRequestCount(2)

    voice.emit(.listening)

    let listeningValue = await snapshots.next()
    let listening = try #require(listeningValue)
    #expect(listening.voice == .listening)
    #expect(listening.basePresence == .parked)
    #expect(voice.startCount == 2)

    await clock.advance(by: .seconds(60))
    let timedOut = try #require(stage.renderedSnapshots.last)
    #expect(timedOut.voice == .ending)
    #expect(voice.startCount == 2)
    #expect(voice.stopCount == 2)
  }

  @Test
  func delayedStartFailureCannotOverwriteACompletedTeardown() async throws {
    for teardown in DelayedStartTeardown.allCases {
      let stage = RecordingStage()
      let voice = DelayedStartVoiceSession()
      let clock = ControllableClock()
      let runtime = CompanionRuntime(
        initialPreferences: CompanionPreferences(),
        stage: stage,
        voice: voice,
        platform: FixedPlatform(),
        clock: clock,
        randomness: FixedRandomSource()
      )

      await runtime.send(.launch)
      let summonTask = Task { @MainActor in
        await runtime.send(.summon(.statusMenu))
      }
      await voice.waitUntilStartIsPending()
      await clock.waitForRequestCount(1)

      let expectedVoice: VoiceSessionState
      switch teardown {
      case .explicitEnd:
        await runtime.send(.endConversation)
        expectedVoice = .ending
      case .timeout:
        await clock.advance(by: .seconds(60))
        expectedVoice = .ending
      case .sleep:
        await runtime.send(.platform(.sleep))
        expectedVoice = .ending
      case .endedEvent:
        voice.emit(.ended)
        await clock.advance(by: .zero)
        expectedVoice = .idle
      }

      voice.failPendingStart()
      await summonTask.value
      await clock.advance(by: .zero)

      let settled = try #require(stage.renderedSnapshots.last)
      #expect(settled.voice == expectedVoice)
      #expect(settled.recoverableError == nil)
      #expect(voice.startCount == 1)
      #expect(voice.stopCount == (teardown == .endedEvent ? 0 : 1))
    }
  }

  @Test
  func endAndHideDismissRecoverableErrorsWithoutStoppingAgain() async throws {
    let failure = CompanionFailure(
      kind: .network,
      message: "Connection lost. Retry when ready."
    )

    do {
      let stage = RecordingStage()
      let voice = ScriptedVoiceSession()
      let clock = ControllableClock()
      let runtime = CompanionRuntime(
        initialPreferences: CompanionPreferences(),
        stage: stage,
        voice: voice,
        platform: FixedPlatform(),
        clock: clock,
        randomness: FixedRandomSource()
      )
      await runtime.send(.launch)
      await runtime.send(.summon(.character))
      voice.emit(.failed(failure))
      await clock.advance(by: .zero)
      #expect(voice.stopCount == 1)

      await runtime.send(.endConversation)
      let dismissed = try #require(stage.renderedSnapshots.last)
      #expect(dismissed.voice == .idle)
      #expect(dismissed.bubble == .hidden)
      #expect(dismissed.recoverableError == nil)
      #expect(voice.stopCount == 1)
    }

    do {
      let stage = RecordingStage()
      let voice = ScriptedVoiceSession()
      let clock = ControllableClock()
      let runtime = CompanionRuntime(
        initialPreferences: CompanionPreferences(),
        stage: stage,
        voice: voice,
        platform: FixedPlatform(),
        clock: clock,
        randomness: FixedRandomSource()
      )
      await runtime.send(.launch)
      await runtime.send(.summon(.statusMenu))
      voice.emit(.failed(failure))
      await clock.advance(by: .zero)
      #expect(voice.stopCount == 1)

      await runtime.send(.setPresence(.hidden))
      let dismissed = try #require(stage.renderedSnapshots.last)
      #expect(dismissed.voice == .idle)
      #expect(dismissed.bubble == .hidden)
      #expect(dismissed.basePresence == .hidden)
      #expect(!dismissed.isVisible)
      #expect(dismissed.recoverableError == nil)
      #expect(voice.stopCount == 1)
    }
  }

  @Test
  func dragParksWithinBoundsAndMoveUsesThePointerDisplay() async throws {
    let initialDisplay = CompanionDisplay(
      id: "built-in",
      visibleFrame: StageRect(
        origin: StagePoint(x: 100, y: 50),
        size: StageSize(width: 1_000, height: 700)
      ),
      scaleFactor: 2
    )
    let externalDisplay = CompanionDisplay(
      id: "external",
      visibleFrame: StageRect(
        origin: StagePoint(x: -1_440, y: 0),
        size: StageSize(width: 1_440, height: 900)
      ),
      scaleFactor: 1
    )
    let platform = MutablePlatform(display: initialDisplay)
    let runtime = CompanionRuntime(
      initialPreferences: CompanionPreferences(),
      stage: RecordingStage(),
      voice: ScriptedVoiceSession(),
      platform: platform,
      clock: ControllableClock(),
      randomness: FixedRandomSource()
    )
    var snapshots = runtime.snapshots.makeAsyncIterator()

    await runtime.send(.launch)
    _ = await snapshots.next()
    await runtime.send(.drag(to: StagePoint(x: 50, y: 800)))

    let draggedValue = await snapshots.next()
    let dragged = try #require(draggedValue)
    #expect(dragged.basePresence == .parked)
    #expect(dragged.placement.displayID == "built-in")
    #expect(dragged.placement.position == StagePoint(x: 164, y: 686))

    platform.display = externalDisplay
    await runtime.send(.moveToCurrentDisplay)

    let movedValue = await snapshots.next()
    let moved = try #require(movedValue)
    #expect(moved.basePresence == .parked)
    #expect(moved.placement.displayID == "external")
    #expect(moved.placement.position == StagePoint(x: -720, y: 450))
    #expect(moved.voice == .idle)
  }

  @Test
  func launchRestoresTheNormalizedParkedPositionSafely() async throws {
    let display = CompanionDisplay(
      id: "current-display",
      visibleFrame: StageRect(
        origin: StagePoint(x: 100, y: 50),
        size: StageSize(width: 1_000, height: 700)
      ),
      scaleFactor: 2
    )
    let runtime = CompanionRuntime(
      initialPreferences: CompanionPreferences(
        presence: .parked,
        parkedPosition: CompanionParkedPosition(
          displayID: "previous-display",
          horizontalFraction: 0.25,
          verticalFraction: 0.75
        )
      ),
      stage: RecordingStage(),
      voice: ScriptedVoiceSession(),
      platform: MutablePlatform(display: display),
      clock: ControllableClock(),
      randomness: FixedRandomSource()
    )
    var snapshots = runtime.snapshots.makeAsyncIterator()

    await runtime.send(.launch)

    let launchValue = await snapshots.next()
    let launched = try #require(launchValue)
    #expect(launched.basePresence == .parked)
    #expect(launched.placement.displayID == "current-display")
    #expect(launched.placement.position == StagePoint(x: 382, y: 543))
    #expect(launched.displayVisibleFrame == display.visibleFrame)
  }

  @Test
  func summonRelocatesOneSessionToThePointerDisplay() async throws {
    let initialDisplay = CompanionDisplay(
      id: "built-in",
      visibleFrame: StageRect(
        origin: StagePoint(x: 0, y: 0),
        size: StageSize(width: 1_200, height: 800)
      ),
      scaleFactor: 2
    )
    let externalDisplay = CompanionDisplay(
      id: "external",
      visibleFrame: StageRect(
        origin: StagePoint(x: -1_600, y: 100),
        size: StageSize(width: 1_600, height: 900)
      ),
      scaleFactor: 1
    )
    let platform = MutablePlatform(display: initialDisplay)
    let voice = ScriptedVoiceSession()
    let stage = RecordingStage()
    let runtime = CompanionRuntime(
      initialPreferences: CompanionPreferences(),
      stage: stage,
      voice: voice,
      platform: platform,
      clock: ControllableClock(),
      randomness: FixedRandomSource()
    )
    var snapshots = runtime.snapshots.makeAsyncIterator()

    await runtime.send(.launch)
    _ = await snapshots.next()

    platform.display = externalDisplay
    await runtime.send(.summon(.keyboardShortcut))

    let connectingValue = await snapshots.next()
    let connecting = try #require(connectingValue)
    #expect(connecting.placement.displayID == "external")
    #expect(connecting.placement.position == StagePoint(x: -800, y: 550))
    #expect(connecting.voice == .connecting)
    #expect(voice.startCount == 1)

    voice.emit(.listening)
    _ = await snapshots.next()

    platform.display = initialDisplay
    await runtime.send(.summon(.statusMenu))

    let revealed = try #require(stage.renderedSnapshots.last)
    #expect(revealed.placement.displayID == "built-in")
    #expect(revealed.placement.position == StagePoint(x: 600, y: 400))
    #expect(revealed.voice == .listening)
    #expect(voice.startCount == 1)
  }

  @Test
  func sleepEndsVoiceAndWakeNeverReconnects() async throws {
    let voice = ScriptedVoiceSession()
    let clock = ControllableClock()
    let runtime = CompanionRuntime(
      initialPreferences: CompanionPreferences(),
      stage: RecordingStage(),
      voice: voice,
      platform: FixedPlatform(),
      clock: clock,
      randomness: FixedRandomSource()
    )
    var snapshots = runtime.snapshots.makeAsyncIterator()

    await runtime.send(.launch)
    _ = await snapshots.next()
    await runtime.send(.summon(.character))
    _ = await snapshots.next()
    voice.emit(.listening)
    _ = await snapshots.next()
    await clock.waitForRequestCount(1)

    await runtime.send(.platform(.sleep))

    let sleepingValue = await snapshots.next()
    let sleeping = try #require(sleepingValue)
    #expect(sleeping.voice == .ending)
    #expect(!sleeping.isVisible)
    #expect(voice.stopCount == 1)

    voice.emit(.ended)

    let asleepValue = await snapshots.next()
    let asleep = try #require(asleepValue)
    #expect(asleep.voice == .idle)
    #expect(!asleep.isVisible)

    await runtime.send(.platform(.wake))

    let awakeValue = await snapshots.next()
    let awake = try #require(awakeValue)
    #expect(awake.voice == .idle)
    #expect(awake.isVisible)
    #expect(voice.startCount == 1)
    #expect(voice.stopCount == 1)

    await clock.advance(by: .seconds(180))
    #expect(voice.startCount == 1)
    #expect(voice.stopCount == 1)
  }

  @Test
  func silentSummonEndsAfterTheFirstSpeechDeadlineExactlyOnce() async throws {
    let stage = RecordingStage()
    let voice = ScriptedVoiceSession()
    let clock = ControllableClock()
    let runtime = CompanionRuntime(
      initialPreferences: CompanionPreferences(),
      stage: stage,
      voice: voice,
      platform: FixedPlatform(),
      clock: clock,
      randomness: FixedRandomSource()
    )

    await runtime.send(.launch)
    await runtime.send(.summon(.statusMenu))
    voice.emit(.listening)
    await clock.waitForRequestCount(1)

    #expect(clock.requestedDurations == [.seconds(60)])
    await clock.advance(by: .seconds(59))
    #expect(voice.stopCount == 0)

    await clock.advance(by: .seconds(1))
    let timedOut = try #require(stage.renderedSnapshots.last)
    #expect(timedOut.voice == .ending)
    #expect(timedOut.bubble == .ending)
    #expect(voice.startCount == 1)
    #expect(voice.stopCount == 1)

    await clock.advance(by: .seconds(600))
    #expect(voice.startCount == 1)
    #expect(voice.stopCount == 1)
    #expect(voice.muteValues.isEmpty)
  }

  @Test
  func committedPersonSpeechStartsAndAloneResetsTheOngoingDeadline() async throws {
    let stage = RecordingStage()
    let voice = ScriptedVoiceSession()
    let clock = ControllableClock()
    let runtime = CompanionRuntime(
      initialPreferences: CompanionPreferences(),
      stage: stage,
      voice: voice,
      platform: FixedPlatform(),
      clock: clock,
      randomness: FixedRandomSource()
    )

    await runtime.send(.launch)
    await runtime.send(.summon(.keyboardShortcut))
    await clock.waitForRequestCount(1)

    voice.emit(.thinking)
    await clock.waitForRequestCount(2)
    #expect(
      clock.requestedDurations == [
        .seconds(60),
        .seconds(120),
      ]
    )

    await clock.advance(by: .seconds(60))
    voice.emit(.speaking)
    await clock.advance(by: .seconds(59))
    #expect(voice.stopCount == 0)

    voice.emit(.thinking)
    await clock.waitForRequestCount(3)
    await clock.advance(by: .seconds(100))
    voice.emit(.listening)
    await clock.advance(by: .seconds(19))
    #expect(voice.stopCount == 0)

    await clock.advance(by: .seconds(1))
    let timedOut = try #require(stage.renderedSnapshots.last)
    #expect(timedOut.voice == .ending)
    #expect(
      clock.requestedDurations == [
        .seconds(60),
        .seconds(120),
        .seconds(120),
      ]
    )
    #expect(voice.startCount == 1)
    #expect(voice.stopCount == 1)
  }

  @Test
  func deinitializationCancelsAStaleInactivityDeadline() async {
    let voice = ScriptedVoiceSession()
    let clock = ControllableClock()
    weak var releasedRuntime: CompanionRuntime?

    do {
      let runtime = CompanionRuntime(
        initialPreferences: CompanionPreferences(),
        stage: RecordingStage(),
        voice: voice,
        platform: FixedPlatform(),
        clock: clock,
        randomness: FixedRandomSource()
      )
      releasedRuntime = runtime
      await runtime.send(.launch)
      await runtime.send(.summon(.character))
      await clock.waitForRequestCount(1)
    }

    await clock.advance(by: .zero)
    #expect(releasedRuntime == nil)
    #expect(clock.cancellationCount == 1)

    await clock.advance(by: .seconds(60))
    #expect(voice.startCount == 1)
    #expect(voice.stopCount == 0)
  }

  @Test
  func muteAndWaveformReflectActualSessionState() async throws {
    let voice = ScriptedVoiceSession()
    let runtime = CompanionRuntime(
      initialPreferences: CompanionPreferences(),
      stage: RecordingStage(),
      voice: voice,
      platform: FixedPlatform(),
      clock: ControllableClock(),
      randomness: FixedRandomSource()
    )
    var snapshots = runtime.snapshots.makeAsyncIterator()

    await runtime.send(.launch)
    _ = await snapshots.next()
    await runtime.send(.summon(.statusMenu))
    _ = await snapshots.next()
    voice.emit(.listening)
    _ = await snapshots.next()
    voice.emit(.audioEnergy(0.72))

    let energizedValue = await snapshots.next()
    let energized = try #require(energizedValue)
    #expect(energized.voice == .listening)
    #expect(energized.waveformEnergy == 0.72)

    await runtime.send(.setMuted(true))

    let mutedValue = await snapshots.next()
    let muted = try #require(mutedValue)
    #expect(muted.voice == .muted)
    #expect(muted.bubble == .muted)
    #expect(muted.waveformEnergy == 0)
    #expect(voice.muteValues == [true])

    voice.emit(.audioEnergy(2))

    let suppressedValue = await snapshots.next()
    let suppressed = try #require(suppressedValue)
    #expect(suppressed.waveformEnergy == 0)

    await runtime.send(.setMuted(false))

    let unmutedValue = await snapshots.next()
    let unmuted = try #require(unmutedValue)
    #expect(unmuted.voice == .listening)
    #expect(unmuted.bubble == .listening)
    #expect(voice.muteValues == [true, false])

    voice.emit(.speaking)
    _ = await snapshots.next()
    voice.emit(.audioEnergy(2))

    let speakingValue = await snapshots.next()
    let speaking = try #require(speakingValue)
    #expect(speaking.voice == .speaking)
    #expect(speaking.waveformEnergy == 1)
  }
}

private enum DelayedStartTeardown: CaseIterable {
  case explicitEnd
  case timeout
  case sleep
  case endedEvent
}

@MainActor
private final class RecordingStage: StagePort {
  private(set) var renderedSnapshots: [CompanionSnapshot] = []

  func render(_ snapshot: CompanionSnapshot) async {
    renderedSnapshots.append(snapshot)
  }
}

@MainActor
private final class DelayedStartVoiceSession: VoiceSessionPort {
  let events: AsyncStream<VoiceSessionEvent>

  private let continuation: AsyncStream<VoiceSessionEvent>.Continuation
  private var pendingStart: CheckedContinuation<Void, any Error>?
  private(set) var startCount = 0
  private(set) var stopCount = 0

  init() {
    let stream = AsyncStream<VoiceSessionEvent>.makeStream()
    events = stream.stream
    continuation = stream.continuation
  }

  func start() async throws {
    startCount += 1
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      pendingStart = continuation
    }
  }

  func stop() async {
    stopCount += 1
  }

  func setMuted(_ isMuted: Bool) async {}

  func emit(_ event: VoiceSessionEvent) {
    continuation.yield(event)
  }

  func waitUntilStartIsPending() async {
    for _ in 0..<100 {
      if pendingStart != nil {
        return
      }
      await Task.yield()
    }
    Issue.record("Expected a pending voice start")
  }

  func failPendingStart() {
    let continuation = pendingStart
    pendingStart = nil
    continuation?.resume(
      throwing: CompanionFailure(
        kind: .network,
        message: "Late start failure."
      )
    )
  }
}

@MainActor
private final class ScriptedVoiceSession: VoiceSessionPort {
  let events: AsyncStream<VoiceSessionEvent>

  private let continuation: AsyncStream<VoiceSessionEvent>.Continuation
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private(set) var muteValues: [Bool] = []

  init() {
    let stream = AsyncStream<VoiceSessionEvent>.makeStream()
    events = stream.stream
    continuation = stream.continuation
  }

  func start() async throws {
    startCount += 1
  }

  func stop() async {
    stopCount += 1
  }

  func setMuted(_ isMuted: Bool) async {
    muteValues.append(isMuted)
  }

  func emit(_ event: VoiceSessionEvent) {
    continuation.yield(event)
  }
}

@MainActor
private struct FixedPlatform: PlatformPort {
  func displayContainingPointer() async -> CompanionDisplay {
    .main
  }
}

@MainActor
private final class MutablePlatform: PlatformPort {
  var display: CompanionDisplay

  init(display: CompanionDisplay) {
    self.display = display
  }

  func displayContainingPointer() async -> CompanionDisplay {
    display
  }
}

@MainActor
private final class ControllableClock: RuntimeClock {
  private struct Sleeper {
    let deadline: Duration
    let continuation: CheckedContinuation<Void, any Error>
  }

  private var now = Duration.zero
  private var nextID = 0
  private var sleepers: [Int: Sleeper] = [:]
  private(set) var requestedDurations: [Duration] = []
  private(set) var cancellationCount = 0

  func sleep(for duration: Duration) async throws {
    let id = nextID
    nextID += 1
    requestedDurations.append(duration)

    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        guard !Task.isCancelled else {
          continuation.resume(throwing: CancellationError())
          return
        }
        sleepers[id] = Sleeper(
          deadline: now + duration,
          continuation: continuation
        )
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.cancelSleep(id: id)
      }
    }
  }

  func waitForRequestCount(_ expectedCount: Int) async {
    for _ in 0..<100 {
      if requestedDurations.count >= expectedCount {
        return
      }
      await Task.yield()
    }
    Issue.record(
      "Expected \(expectedCount) clock requests, got \(requestedDurations.count)"
    )
  }

  func advance(by duration: Duration) async {
    now += duration
    let readyIDs = sleepers.compactMap { id, sleeper in
      sleeper.deadline <= now ? id : nil
    }
    let ready = readyIDs.compactMap { sleepers.removeValue(forKey: $0) }
    for sleeper in ready {
      sleeper.continuation.resume()
    }
    for _ in 0..<8 {
      await Task.yield()
    }
  }

  private func cancelSleep(id: Int) {
    guard let sleeper = sleepers.removeValue(forKey: id) else {
      return
    }
    cancellationCount += 1
    sleeper.continuation.resume(throwing: CancellationError())
  }
}

@MainActor
private struct FixedRandomSource: RandomSource {
  func nextUnitInterval() -> Double {
    0.5
  }
}
