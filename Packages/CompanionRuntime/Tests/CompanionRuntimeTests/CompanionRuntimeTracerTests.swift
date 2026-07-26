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
private struct ImmediateClock: RuntimeClock {
  func sleep(for duration: Duration) async throws {}
}

@MainActor
private struct FixedRandomSource: RandomSource {
  func nextUnitInterval() -> Double {
    0.5
  }
}
