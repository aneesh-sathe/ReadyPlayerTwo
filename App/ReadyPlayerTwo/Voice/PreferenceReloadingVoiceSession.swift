import CompanionRuntime

@MainActor
final class PreferenceReloadingVoiceSession: VoiceSessionPort {
  typealias Builder =
    @MainActor (RealtimeVoiceConfiguration) throws -> any VoiceSessionPort

  let events: AsyncStream<VoiceSessionEvent>

  private let preferencesStore: any InterfacePreferencesStoring
  private let builder: Builder
  private let continuation: AsyncStream<VoiceSessionEvent>.Continuation

  private var currentSession: (any VoiceSessionPort)?
  private var eventTask: Task<Void, Never>?
  private var generation = 0

  init(
    preferencesStore: any InterfacePreferencesStoring,
    builder: @escaping Builder
  ) {
    self.preferencesStore = preferencesStore
    self.builder = builder

    let pair = AsyncStream<VoiceSessionEvent>.makeStream()
    events = pair.stream
    continuation = pair.continuation
  }

  func start() async throws {
    guard currentSession == nil else {
      return
    }

    let defaults = RealtimeVoiceConfiguration.companionV1
    let preferences = preferencesStore.load()
    let configuration = RealtimeVoiceConfiguration(
      model: preferences.modelIdentifier ?? defaults.model,
      voice: preferences.voiceIdentifier ?? defaults.voice,
      instructions: defaults.instructions
    )
    let session: any VoiceSessionPort
    do {
      session = try builder(configuration)
    } catch let failure as CompanionFailure {
      throw failure
    } catch {
      throw CompanionFailure(
        kind: .voiceNotConfigured,
        message: "Voice configuration is incomplete."
      )
    }

    generation &+= 1
    let sessionGeneration = generation
    currentSession = session
    observe(session.events, generation: sessionGeneration)

    do {
      try await session.start()
    } catch {
      finish(generation: sessionGeneration)
      throw error
    }
  }

  func stop() async {
    guard let currentSession else {
      return
    }

    await currentSession.stop()
  }

  func setMuted(_ isMuted: Bool) async {
    await currentSession?.setMuted(isMuted)
  }

  private func observe(
    _ sessionEvents: AsyncStream<VoiceSessionEvent>,
    generation sessionGeneration: Int
  ) {
    eventTask?.cancel()
    eventTask = Task { @MainActor [weak self] in
      for await event in sessionEvents {
        guard let self, !Task.isCancelled else {
          return
        }
        continuation.yield(event)
        switch event {
        case .ended, .failed:
          finish(generation: sessionGeneration)
          return
        case .listening, .thinking, .speaking, .muted, .audioEnergy:
          break
        }
      }
    }
  }

  private func finish(generation sessionGeneration: Int) {
    guard generation == sessionGeneration else {
      return
    }

    eventTask?.cancel()
    eventTask = nil
    currentSession = nil
  }
}
