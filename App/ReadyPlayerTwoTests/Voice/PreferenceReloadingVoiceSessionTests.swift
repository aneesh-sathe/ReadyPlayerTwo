import CompanionRuntime
import Testing

@testable import ReadyPlayerTwo

@MainActor
struct PreferenceReloadingVoiceSessionTests {
  @Test
  func nextSummonUsesLatestPersistedVoiceConfiguration() async throws {
    let store = PreferenceReloadingStore(
      preferences: LocalInterfacePreferences(
        voiceIdentifier: "marin",
        modelIdentifier: "gpt-realtime-2.1"
      )
    )
    var configurations: [RealtimeVoiceConfiguration] = []
    var sessions: [PreferenceReloadingInnerSession] = []
    let session = PreferenceReloadingVoiceSession(
      preferencesStore: store
    ) { configuration in
      configurations.append(configuration)
      let inner = PreferenceReloadingInnerSession()
      sessions.append(inner)
      return inner
    }
    var events = session.events.makeAsyncIterator()

    try await session.start()
    #expect(configurations.map(\.voice) == ["marin"])

    sessions[0].emit(.listening)
    #expect(await events.next() == .listening)
    await session.stop()
    #expect(await events.next() == .ended)

    try store.save(
      LocalInterfacePreferences(
        voiceIdentifier: "cedar",
        modelIdentifier: "gpt-realtime-2.1"
      )
    )
    try await session.start()

    #expect(configurations.map(\.voice) == ["marin", "cedar"])
    #expect(sessions.count == 2)
  }

  @Test
  func malformedBrokerConfigurationFailsWithRedactedTypedError() async {
    let store = PreferenceReloadingStore(preferences: .defaults)
    let session = ProductionVoiceSessionFactory.make(
      environment: [
        "READYPLAYERTWO_VOICE_CONFIGURED": "1"
      ],
      preferencesStore: store
    )

    do {
      try await session.start()
      Issue.record("Expected incomplete voice configuration to fail.")
    } catch let failure as CompanionFailure {
      #expect(failure.kind == .voiceNotConfigured)
      #expect(failure.message == "Voice configuration is incomplete.")
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }
}

@MainActor
private final class PreferenceReloadingStore:
  InterfacePreferencesStoring
{
  private var preferences: LocalInterfacePreferences

  init(preferences: LocalInterfacePreferences) {
    self.preferences = preferences
  }

  func load() -> LocalInterfacePreferences {
    preferences
  }

  func save(_ preferences: LocalInterfacePreferences) throws {
    self.preferences = preferences
  }

  func clear() {}
}

@MainActor
private final class PreferenceReloadingInnerSession: VoiceSessionPort {
  let events: AsyncStream<VoiceSessionEvent>
  private let continuation: AsyncStream<VoiceSessionEvent>.Continuation

  init() {
    let pair = AsyncStream<VoiceSessionEvent>.makeStream()
    events = pair.stream
    continuation = pair.continuation
  }

  func start() async throws {}

  func stop() async {
    continuation.yield(.ended)
  }

  func setMuted(_: Bool) async {}

  func emit(_ event: VoiceSessionEvent) {
    continuation.yield(event)
  }
}
