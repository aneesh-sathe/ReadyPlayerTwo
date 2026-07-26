import AppKit
import CompanionRuntime

@MainActor
final class UnavailableVoiceSession: VoiceSessionPort {
  let events: AsyncStream<VoiceSessionEvent>

  init() {
    events = AsyncStream { _ in }
  }

  func start() async throws {
    throw CompanionFailure(
      kind: .voiceNotConfigured,
      message: "Voice is not configured in this build."
    )
  }

  func stop() async {}

  func setMuted(_ isMuted: Bool) async {}
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
