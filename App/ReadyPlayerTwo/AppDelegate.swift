import AppKit
import CompanionRuntime

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var coordinator: ApplicationCoordinator?
  private var runtime: CompanionRuntime?
  private var shortcutController: GlobalShortcutController?
  private var platformEventMonitor: MacPlatformEventMonitor?

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
    let conversationPresenter = ConversationPanelController(
      actions: ConversationBubbleActions(
        setMuted: { isMuted in
          Task {
            await runtime.send(.setMuted(isMuted))
          }
        },
        retry: {
          Task {
            await runtime.send(.retryConversation)
          }
        },
        end: {
          Task {
            await runtime.send(.endConversation)
          }
        }
      )
    )
    let coordinator = ApplicationCoordinator(
      runtime: runtime,
      statusMenu: StatusMenuController(),
      application: NSApplication.shared,
      conversationPresenter: conversationPresenter,
      preferencesStore: preferencesStore,
      initialPreferences: preferences
    )
    let shortcutController = GlobalShortcutController(
      registrar: CarbonGlobalShortcutRegistrar()
    )
    _ = shortcutController.activate(preferences.shortcut) {
      Task {
        await runtime.send(.summon(.keyboardShortcut))
      }
    }
    let platformEventMonitor = MacPlatformEventMonitor { event in
      await runtime.send(.platform(event))
    }
    platformEventMonitor.start()

    self.coordinator = coordinator
    self.runtime = runtime
    self.shortcutController = shortcutController
    self.platformEventMonitor = platformEventMonitor

    Task {
      await coordinator.start()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    shortcutController?.deactivate()
    platformEventMonitor?.stop()
  }
}
