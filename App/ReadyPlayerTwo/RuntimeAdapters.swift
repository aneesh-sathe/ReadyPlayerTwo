import AppKit
import CompanionRuntime

@MainActor
final class UnavailableVoiceSession: VoiceSessionPort {
  let events: AsyncStream<VoiceSessionEvent>

  private let failure: CompanionFailure

  init(
    failure: CompanionFailure = CompanionFailure(
      kind: .voiceNotConfigured,
      message: "Voice is not configured in this build."
    )
  ) {
    self.failure = failure
    events = AsyncStream { _ in }
  }

  func start() async throws {
    throw failure
  }

  func stop() async {}

  func setMuted(_ isMuted: Bool) async {}
}

@MainActor
enum ProductionVoiceSessionFactory {
  private static let configuredKey =
    "READYPLAYERTWO_VOICE_CONFIGURED"

  static func make(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    configuration: RealtimeVoiceConfiguration = .companionV1
  ) -> any VoiceSessionPort {
    guard environment[configuredKey] == "1" else {
      return UnavailableVoiceSession()
    }

    do {
      let broker = try BrokerClient(
        environment: environment,
        configuration: configuration
      )
      let transport = try WebRTCRealtimeTransport()
      return OpenAIRealtimeVoiceSession(
        broker: broker,
        transport: transport,
        configuration: configuration
      )
    } catch {
      return UnavailableVoiceSession(
        failure: CompanionFailure(
          kind: .voiceNotConfigured,
          message: "Voice configuration is incomplete."
        )
      )
    }
  }

  static func make(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    preferencesStore: any InterfacePreferencesStoring
  ) -> any VoiceSessionPort {
    guard environment[configuredKey] == "1" else {
      return UnavailableVoiceSession()
    }

    return PreferenceReloadingVoiceSession(
      preferencesStore: preferencesStore
    ) { configuration in
      let broker = try BrokerClient(
        environment: environment,
        configuration: configuration
      )
      let transport = try WebRTCRealtimeTransport()
      return OpenAIRealtimeVoiceSession(
        broker: broker,
        transport: transport,
        configuration: configuration
      )
    }
  }
}

@MainActor
struct MacPlatform: PlatformPort {
  func displayContainingPointer() async -> CompanionDisplay {
    let pointer = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
      ?? NSScreen.main
      ?? NSScreen.screens.first

    guard let screen else {
      return .main
    }

    let frame = screen.visibleFrame
    let screenNumber =
      screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
      as? NSNumber

    return CompanionDisplay(
      id: screenNumber?.stringValue ?? "main",
      visibleFrame: StageRect(
        origin: StagePoint(x: frame.origin.x, y: frame.origin.y),
        size: StageSize(width: frame.width, height: frame.height)
      ),
      scaleFactor: screen.backingScaleFactor
    )
  }
}

@MainActor
struct SystemRuntimeClock: RuntimeClock {
  func sleep(for duration: Duration) async throws {
    try await Task.sleep(for: duration)
  }
}

@MainActor
struct SystemRandomSource: RandomSource {
  func nextUnitInterval() -> Double {
    Double.random(in: 0..<1)
  }
}
