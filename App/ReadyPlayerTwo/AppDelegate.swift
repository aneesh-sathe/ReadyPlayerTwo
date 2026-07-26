import AppKit
import CompanionRuntime

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var coordinator: ApplicationCoordinator?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    let stage = CompanionStage(bundle: .main)
    let runtime = CompanionRuntime(
      initialPreferences: CompanionPreferences(),
      stage: stage,
      voice: UnavailableVoiceSession(),
      platform: MacPlatform(),
      clock: SystemRuntimeClock(),
      randomness: SystemRandomSource()
    )
    let coordinator = ApplicationCoordinator(
      runtime: runtime,
      statusMenu: StatusMenuController(),
      application: NSApplication.shared
    )

    self.coordinator = coordinator

    Task {
      await coordinator.start()
    }
  }
}
