import AppKit
import CompanionRuntime

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var coordinator: ApplicationCoordinator?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    let preferencesStore = UserDefaultsInterfacePreferencesStore()
    let preferences = preferencesStore.load()
    let defaultVoice = RealtimeVoiceConfiguration.companionV1
    let voiceConfiguration = RealtimeVoiceConfiguration(
      model: preferences.modelIdentifier ?? defaultVoice.model,
      voice: preferences.voiceIdentifier ?? defaultVoice.voice,
      instructions: defaultVoice.instructions
    )
    let stage = CompanionStage(bundle: .main)
    let runtime = CompanionRuntime(
      initialPreferences: CompanionPreferences(
        avatar: preferences.avatar,
        presence: preferences.presence
      ),
      stage: stage,
      voice: ProductionVoiceSessionFactory.make(
        configuration: voiceConfiguration
      ),
      platform: MacPlatform(),
      clock: SystemRuntimeClock(),
      randomness: SystemRandomSource()
    )
    let coordinator = ApplicationCoordinator(
      runtime: runtime,
      statusMenu: StatusMenuController(),
      application: NSApplication.shared,
      preferencesStore: preferencesStore,
      initialPreferences: preferences
    )
    self.coordinator = coordinator

    Task {
      await coordinator.start()
    }
  }
}
