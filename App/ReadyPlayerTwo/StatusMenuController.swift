import AppKit
import CompanionRuntime

enum VoiceReadiness: Equatable, Sendable {
  case checking
  case ready
  case notConfigured
  case brokerUnavailable

  var idleVoiceDescription: String {
    switch self {
    case .checking:
      "Voice: Checking"
    case .ready:
      "Voice: Ready"
    case .notConfigured:
      "Voice: Not Configured"
    case .brokerUnavailable:
      "Voice: Unavailable"
    }
  }

  var brokerDescription: String {
    switch self {
    case .checking:
      "Broker: Checking"
    case .ready, .notConfigured:
      "Broker: Healthy"
    case .brokerUnavailable:
      "Broker: Unavailable"
    }
  }
}

struct StatusMenuPresentation: Equatable {
  let conversationTitle: String
  let conversationEnabled: Bool
  let muteTitle: String
  let muteVisible: Bool
  let hideOrShowTitle: String
  let selectedPresence: PresenceState
  let selectedAvatar: CompanionAvatar
  let voiceDescription: String
  let brokerDescription: String
  let microphoneDescription: String
  let processingDescription: String

  init(
    snapshot: CompanionSnapshot,
    voiceReadiness: VoiceReadiness = .checking
  ) {
    selectedPresence = snapshot.basePresence
    selectedAvatar = snapshot.avatar
    hideOrShowTitle =
      snapshot.basePresence == .hidden ? "Show Companion" : "Hide Companion"
    processingDescription = "Voice Processing: Remote via OpenAI"
    brokerDescription = voiceReadiness.brokerDescription

    switch snapshot.voice {
    case .idle:
      conversationTitle = "Summon"
      conversationEnabled = true
      muteTitle = "Mute Microphone"
      muteVisible = false
      voiceDescription = voiceReadiness.idleVoiceDescription
      microphoneDescription = "Microphone: Off"
    case .connecting:
      conversationTitle = "End Conversation"
      conversationEnabled = true
      muteTitle = "Mute Microphone"
      muteVisible = true
      voiceDescription = "Voice: Connecting"
      microphoneDescription = "Microphone: Starting"
    case .listening:
      conversationTitle = "End Conversation"
      conversationEnabled = true
      muteTitle = "Mute Microphone"
      muteVisible = true
      voiceDescription = "Voice: Listening"
      microphoneDescription = "Microphone: On"
    case .thinking:
      conversationTitle = "End Conversation"
      conversationEnabled = true
      muteTitle = "Mute Microphone"
      muteVisible = true
      voiceDescription = "Voice: Thinking"
      microphoneDescription = "Microphone: On"
    case .speaking:
      conversationTitle = "End Conversation"
      conversationEnabled = true
      muteTitle = "Mute Microphone"
      muteVisible = true
      voiceDescription = "Voice: Speaking"
      microphoneDescription = "Microphone: On"
    case .muted:
      conversationTitle = "End Conversation"
      conversationEnabled = true
      muteTitle = "Unmute Microphone"
      muteVisible = true
      voiceDescription = "Voice: Muted"
      microphoneDescription = "Microphone: Muted"
    case .error(let failure):
      conversationTitle = "Retry Voice"
      conversationEnabled = true
      muteTitle = "Mute Microphone"
      muteVisible = false
      voiceDescription = "Voice: Error (\(failure.kind.rawValue))"
      microphoneDescription = "Microphone: Off"
    case .ending:
      conversationTitle = "Ending Conversation"
      conversationEnabled = false
      muteTitle = "Mute Microphone"
      muteVisible = false
      voiceDescription = "Voice: Ending"
      microphoneDescription = "Microphone: Closing"
    }
  }
}

@MainActor
final class StatusMenuController: NSObject, StatusMenuPresenting {
  private let shortcutSettingsPresenter: (any ShortcutSettingsPresenting)?
  private let voiceSettingsPresenter: (any VoiceSettingsPresenting)?
  private var actions: StatusMenuActions?
  private var statusItem: NSStatusItem?
  private var conversationItem: NSMenuItem?
  private var muteItem: NSMenuItem?
  private var roamItem: NSMenuItem?
  private var parkItem: NSMenuItem?
  private var hideOrShowItem: NSMenuItem?
  private var orionItem: NSMenuItem?
  private var athenaItem: NSMenuItem?
  private var voiceDiagnosticItem: NSMenuItem?
  private var brokerDiagnosticItem: NSMenuItem?
  private var microphoneDiagnosticItem: NSMenuItem?
  private var latestSnapshot: CompanionSnapshot?
  private var voiceReadiness = VoiceReadiness.checking

  var installedMenu: NSMenu? {
    statusItem?.menu
  }

  init(
    shortcutSettingsPresenter:
      (any ShortcutSettingsPresenting)? = nil,
    voiceSettingsPresenter:
      (any VoiceSettingsPresenting)? = nil
  ) {
    self.shortcutSettingsPresenter = shortcutSettingsPresenter
    self.voiceSettingsPresenter = voiceSettingsPresenter
    super.init()
  }

  func install(actions: StatusMenuActions) {
    guard statusItem == nil else {
      return
    }

    self.actions = actions

    let statusItem = NSStatusBar.system.statusItem(
      withLength: NSStatusItem.squareLength
    )
    statusItem.autosaveName = "ReadyPlayerTwo.StatusItem"

    if let button = statusItem.button {
      let image = NSImage(
        systemSymbolName: "person.crop.circle",
        accessibilityDescription: "ReadyPlayerTwo"
      )
      image?.isTemplate = true
      button.image = image

      if image == nil {
        button.title = "RP2"
      }

      button.toolTip = "ReadyPlayerTwo"
      button.setAccessibilityIdentifier("status.menu")
    }

    let menu = NSMenu(title: "ReadyPlayerTwo")
    conversationItem = addItem(
      to: menu,
      title: "Summon",
      action: #selector(summonOrEnd),
      accessibilityIdentifier: "status.conversation"
    )
    muteItem = addItem(
      to: menu,
      title: "Mute Microphone",
      action: #selector(muteOrUnmute),
      accessibilityIdentifier: "status.mute"
    )
    muteItem?.isHidden = true

    menu.addItem(.separator())
    roamItem = addItem(
      to: menu,
      title: "Roam",
      action: #selector(roam),
      accessibilityIdentifier: "status.roam"
    )
    parkItem = addItem(
      to: menu,
      title: "Park",
      action: #selector(park),
      accessibilityIdentifier: "status.park"
    )
    hideOrShowItem = addItem(
      to: menu,
      title: "Hide Companion",
      action: #selector(hideOrShow),
      accessibilityIdentifier: "status.hide-or-show"
    )
    _ = addItem(
      to: menu,
      title: "Move to Current Display",
      action: #selector(moveToCurrentDisplay),
      accessibilityIdentifier: "status.move-display"
    )

    let companionItem = NSMenuItem(title: "Companion", action: nil, keyEquivalent: "")
    companionItem.setAccessibilityIdentifier("status.companion")
    let companionMenu = NSMenu(title: "Companion")
    orionItem = addItem(
      to: companionMenu,
      title: "Orion",
      action: #selector(selectOrion),
      accessibilityIdentifier: "status.avatar.orion"
    )
    athenaItem = addItem(
      to: companionMenu,
      title: "Athena",
      action: #selector(selectAthena),
      accessibilityIdentifier: "status.avatar.athena"
    )
    companionItem.submenu = companionMenu
    menu.addItem(companionItem)

    _ = addItem(
      to: menu,
      title: "Keyboard Shortcut…",
      action: #selector(showShortcutSettings),
      accessibilityIdentifier: "status.shortcut-settings"
    )
    _ = addItem(
      to: menu,
      title: "Voice Settings…",
      action: #selector(showVoiceSettings),
      accessibilityIdentifier: "status.voice-settings"
    )

    let diagnosticsItem = NSMenuItem(
      title: "Diagnostics",
      action: nil,
      keyEquivalent: ""
    )
    let diagnosticsMenu = NSMenu(title: "Diagnostics")
    voiceDiagnosticItem = NSMenuItem(
      title: voiceReadiness.idleVoiceDescription,
      action: nil,
      keyEquivalent: ""
    )
    microphoneDiagnosticItem = NSMenuItem(
      title: "Microphone: Off",
      action: nil,
      keyEquivalent: ""
    )
    brokerDiagnosticItem = NSMenuItem(
      title: voiceReadiness.brokerDescription,
      action: nil,
      keyEquivalent: ""
    )
    let processingDiagnosticItem = NSMenuItem(
      title: "Voice Processing: Remote via OpenAI",
      action: nil,
      keyEquivalent: ""
    )
    if let voiceDiagnosticItem {
      diagnosticsMenu.addItem(voiceDiagnosticItem)
    }
    if let brokerDiagnosticItem {
      diagnosticsMenu.addItem(brokerDiagnosticItem)
    }
    if let microphoneDiagnosticItem {
      diagnosticsMenu.addItem(microphoneDiagnosticItem)
    }
    diagnosticsMenu.addItem(processingDiagnosticItem)
    diagnosticsItem.submenu = diagnosticsMenu
    menu.addItem(diagnosticsItem)

    menu.addItem(.separator())
    _ = addItem(
      to: menu,
      title: "Quit ReadyPlayerTwo",
      action: #selector(quit),
      accessibilityIdentifier: "status.quit",
      keyEquivalent: "q"
    )

    statusItem.menu = menu
    self.statusItem = statusItem
  }

  func uninstall() {
    guard let statusItem else {
      return
    }

    NSStatusBar.system.removeStatusItem(statusItem)
    self.statusItem = nil
    actions = nil
    latestSnapshot = nil
    voiceReadiness = .checking
  }

  func render(_ snapshot: CompanionSnapshot) {
    latestSnapshot = snapshot
    let presentation = StatusMenuPresentation(
      snapshot: snapshot,
      voiceReadiness: voiceReadiness
    )
    conversationItem?.title = presentation.conversationTitle
    conversationItem?.isEnabled = presentation.conversationEnabled
    muteItem?.title = presentation.muteTitle
    muteItem?.isHidden = !presentation.muteVisible
    hideOrShowItem?.title = presentation.hideOrShowTitle
    roamItem?.state =
      presentation.selectedPresence == .roaming ? .on : .off
    parkItem?.state =
      presentation.selectedPresence == .parked ? .on : .off
    orionItem?.state =
      presentation.selectedAvatar == .orion ? .on : .off
    athenaItem?.state =
      presentation.selectedAvatar == .athena ? .on : .off
    voiceDiagnosticItem?.title = presentation.voiceDescription
    brokerDiagnosticItem?.title = presentation.brokerDescription
    microphoneDiagnosticItem?.title = presentation.microphoneDescription
  }

  func renderVoiceReadiness(_ voiceReadiness: VoiceReadiness) {
    self.voiceReadiness = voiceReadiness
    guard let latestSnapshot else {
      voiceDiagnosticItem?.title =
        voiceReadiness.idleVoiceDescription
      brokerDiagnosticItem?.title =
        voiceReadiness.brokerDescription
      return
    }
    render(latestSnapshot)
  }

  private func addItem(
    to menu: NSMenu,
    title: String,
    action: Selector,
    accessibilityIdentifier: String,
    keyEquivalent: String = ""
  ) -> NSMenuItem {
    let item = NSMenuItem(
      title: title,
      action: action,
      keyEquivalent: keyEquivalent
    )
    item.target = self
    item.setAccessibilityIdentifier(accessibilityIdentifier)
    menu.addItem(item)
    return item
  }

  @objc
  private func summonOrEnd() {
    Task {
      await actions?.summonOrEnd()
    }
  }

  @objc
  private func muteOrUnmute() {
    Task {
      await actions?.muteOrUnmute()
    }
  }

  @objc
  private func roam() {
    Task {
      await actions?.roam()
    }
  }

  @objc
  private func park() {
    Task {
      await actions?.park()
    }
  }

  @objc
  private func hideOrShow() {
    Task {
      await actions?.hideOrShow()
    }
  }

  @objc
  private func moveToCurrentDisplay() {
    Task {
      await actions?.moveToCurrentDisplay()
    }
  }

  @objc
  private func selectOrion() {
    Task {
      await actions?.selectAvatar(.orion)
    }
  }

  @objc
  private func selectAthena() {
    Task {
      await actions?.selectAvatar(.athena)
    }
  }

  @objc
  private func showShortcutSettings() {
    guard
      let positioningView = statusItem?.button,
      let shortcutSettingsPresenter
    else {
      return
    }

    shortcutSettingsPresenter.show(
      relativeTo: positioningView
    )
  }

  @objc
  private func showVoiceSettings() {
    guard
      let positioningView = statusItem?.button,
      let voiceSettingsPresenter
    else {
      return
    }

    voiceSettingsPresenter.show(
      relativeTo: positioningView
    )
  }

  @objc
  private func quit() {
    Task {
      await actions?.quit()
    }
  }
}
