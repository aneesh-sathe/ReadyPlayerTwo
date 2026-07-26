import CompanionRuntime
import Testing

@Suite(.serialized)
@MainActor
struct CompanionRuntimeTracerTests {
  @Test
  func explicitSummonIsSingletonAndRestoresRoaming() async throws {
    let stage = RecordingStage()
    let voice = ScriptedVoiceSession()
    let runtime = CompanionRuntime(
      initialPreferences: CompanionPreferences(
        avatar: .orion,
        presence: .roaming
      ),
      stage: stage,
      voice: voice,
      platform: FixedPlatform(),
      clock: ImmediateClock(),
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

    await runtime.send(.summon(.keyboardShortcut))
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
  }

  @Test
  func presenceControlsStaySilentAndHideEndsConversation() async throws {
    let voice = ScriptedVoiceSession()
    let runtime = CompanionRuntime(
      initialPreferences: CompanionPreferences(),
      stage: RecordingStage(),
      voice: voice,
      platform: FixedPlatform(),
      clock: ImmediateClock(),
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
      clock: ImmediateClock(),
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
    let runtime = CompanionRuntime(
      initialPreferences: CompanionPreferences(presence: .parked),
      stage: RecordingStage(),
      voice: voice,
      platform: FixedPlatform(),
      clock: ImmediateClock(),
      randomness: FixedRandomSource()
    )
    var snapshots = runtime.snapshots.makeAsyncIterator()

    await runtime.send(.launch)
    _ = await snapshots.next()
    await runtime.send(.summon(.keyboardShortcut))
    _ = await snapshots.next()

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

    await runtime.send(.retryConversation)

    let retryValue = await snapshots.next()
    let retry = try #require(retryValue)
    #expect(retry.voice == .connecting)
    #expect(retry.recoverableError == nil)
    #expect(voice.startCount == 2)

    voice.emit(.listening)

    let listeningValue = await snapshots.next()
    let listening = try #require(listeningValue)
    #expect(listening.voice == .listening)
    #expect(listening.basePresence == .parked)
    #expect(voice.startCount == 2)
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
      clock: ImmediateClock(),
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
}

@MainActor
private final class RecordingStage: StagePort {
  private(set) var renderedSnapshots: [CompanionSnapshot] = []

  func render(_ snapshot: CompanionSnapshot) async {
    renderedSnapshots.append(snapshot)
  }
}

@MainActor
private final class ScriptedVoiceSession: VoiceSessionPort {
  let events: AsyncStream<VoiceSessionEvent>

  private let continuation: AsyncStream<VoiceSessionEvent>.Continuation
  private(set) var startCount = 0
  private(set) var stopCount = 0

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

  func setMuted(_ isMuted: Bool) async {}

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
private struct ImmediateClock: RuntimeClock {
  func sleep(for duration: Duration) async throws {}
}

@MainActor
private struct FixedRandomSource: RandomSource {
  func nextUnitInterval() -> Double {
    0.5
  }
}
