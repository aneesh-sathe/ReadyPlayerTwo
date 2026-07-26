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

    let launchMode = ApplicationLaunchMode.resolve()
    let preferencesStore = launchMode.makePreferencesStore()
    let preferences = preferencesStore.load()
    let stageActions = CompanionStageActions()
    let stage = CompanionStage(
      bundle: .main,
      actions: stageActions
    )
    let runtime = CompanionRuntime(
      initialPreferences: CompanionPreferences(
        avatar: preferences.avatar,
        presence: preferences.presence,
        parkedPosition: preferences.parkedPosition
      ),
      stage: stage,
      voice: ProductionVoiceSessionFactory.make(
        preferencesStore: preferencesStore
      ),
      platform: MacPlatform(),
      clock: SystemRuntimeClock(),
      randomness: SystemRandomSource()
    )
    stageActions.connect(
      summon: { [weak runtime] in
        await runtime?.send(.summon(.character))
      },
      dragToPark: { [weak runtime] point in
        await runtime?.send(.drag(to: point))
      }
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
    let shortcutRegistrar = CarbonGlobalShortcutRegistrar()
    let shortcutController = GlobalShortcutController(
      registrar: shortcutRegistrar
    )
    let shortcutInvocation: @MainActor () -> Void = {
      [weak runtime] in
      Task {
        await runtime?.send(.summon(.keyboardShortcut))
      }
    }
    if launchMode.registersGlobalShortcut {
      _ = shortcutController.activate(
        preferences.shortcut,
        onInvocation: shortcutInvocation
      )
    }
    let shortcutSettings =
      ShortcutSettingsPopoverController(
        shortcutController: shortcutController,
        availabilityRegistrar: shortcutRegistrar,
        preferencesStore: preferencesStore,
        onShortcutInvocation: shortcutInvocation
      )
    let voiceSettings = VoiceSettingsPopoverController(
      preferencesStore: preferencesStore,
      openSoundSettings: {
        guard
          let url = URL(
            string:
              "x-apple.systempreferences:com.apple.Sound-Settings.extension"
          )
        else {
          return
        }
        NSWorkspace.shared.open(url)
      }
    )
    let coordinator = ApplicationCoordinator(
      runtime: runtime,
      statusMenu: StatusMenuController(
        shortcutSettingsPresenter: shortcutSettings,
        voiceSettingsPresenter: voiceSettings
      ),
      application: NSApplication.shared,
      conversationPresenter: conversationPresenter,
      preferencesStore: preferencesStore,
      initialPreferences: preferences,
      voiceReadinessChecker:
        launchMode.makeVoiceReadinessChecker()
    )
    let platformEventMonitor = MacPlatformEventMonitor { event in
      await runtime.send(.platform(event))
    }
    if launchMode.monitorsPlatformEvents {
      platformEventMonitor.start()
    }

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
