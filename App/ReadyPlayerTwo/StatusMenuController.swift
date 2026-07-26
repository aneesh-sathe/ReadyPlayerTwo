import AppKit
import CompanionRuntime

struct StatusMenuPresentation: Equatable {
  let conversationTitle: String
  let conversationEnabled: Bool
  let muteTitle: String
  let muteVisible: Bool
  let hideOrShowTitle: String
  let selectedPresence: PresenceState
  let selectedAvatar: CompanionAvatar
  let voiceDescription: String
  let microphoneDescription: String

  init(snapshot: CompanionSnapshot) {
    selectedPresence = snapshot.basePresence
    selectedAvatar = snapshot.avatar
    hideOrShowTitle =
      snapshot.basePresence == .hidden ? "Show Companion" : "Hide Companion"

    switch snapshot.voice {
    case .idle:
      conversationTitle = "Summon"
      conversationEnabled = true
      muteTitle = "Mute Microphone"
      muteVisible = false
      voiceDescription = "Voice: Idle"
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
  private var microphoneDiagnosticItem: NSMenuItem?

  var installedMenu: NSMenu? {
    statusItem?.menu
  }

  init(
    shortcutSettingsPresenter:
      (any ShortcutSettingsPresenting)? = nil
  ) {
    self.shortcutSettingsPresenter = shortcutSettingsPresenter
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
    }

    let menu = NSMenu(title: "ReadyPlayerTwo")
    conversationItem = addItem(
      to: menu,
      title: "Summon",
      action: #selector(summonOrEnd)
    )
    muteItem = addItem(
      to: menu,
      title: "Mute Microphone",
      action: #selector(muteOrUnmute)
    )
    muteItem?.isHidden = true

    menu.addItem(.separator())
    roamItem = addItem(
      to: menu,
      title: "Roam",
      action: #selector(roam)
    )
    parkItem = addItem(
      to: menu,
      title: "Park",
      action: #selector(park)
    )
    hideOrShowItem = addItem(
      to: menu,
      title: "Hide Companion",
      action: #selector(hideOrShow)
    )
    _ = addItem(
      to: menu,
      title: "Move to Current Display",
      action: #selector(moveToCurrentDisplay)
    )

    let companionItem = NSMenuItem(title: "Companion", action: nil, keyEquivalent: "")
    let companionMenu = NSMenu(title: "Companion")
    orionItem = addItem(
      to: companionMenu,
      title: "Orion",
      action: #selector(selectOrion)
    )
    athenaItem = addItem(
      to: companionMenu,
      title: "Athena",
      action: #selector(selectAthena)
    )
    companionItem.submenu = companionMenu
    menu.addItem(companionItem)

    _ = addItem(
      to: menu,
      title: "Keyboard Shortcut…",
      action: #selector(showShortcutSettings)
    )

    let diagnosticsItem = NSMenuItem(
      title: "Diagnostics",
      action: nil,
      keyEquivalent: ""
    )
    let diagnosticsMenu = NSMenu(title: "Diagnostics")
    voiceDiagnosticItem = NSMenuItem(
      title: "Voice: Starting",
      action: nil,
      keyEquivalent: ""
    )
    microphoneDiagnosticItem = NSMenuItem(
      title: "Microphone: Off",
      action: nil,
      keyEquivalent: ""
    )
    if let voiceDiagnosticItem {
      diagnosticsMenu.addItem(voiceDiagnosticItem)
    }
    if let microphoneDiagnosticItem {
      diagnosticsMenu.addItem(microphoneDiagnosticItem)
    }
    diagnosticsItem.submenu = diagnosticsMenu
    menu.addItem(diagnosticsItem)

    menu.addItem(.separator())
    _ = addItem(
      to: menu,
      title: "Quit ReadyPlayerTwo",
      action: #selector(quit),
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
  }

  func render(_ snapshot: CompanionSnapshot) {
    let presentation = StatusMenuPresentation(snapshot: snapshot)
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
    microphoneDiagnosticItem?.title = presentation.microphoneDescription
  }

  private func addItem(
    to menu: NSMenu,
    title: String,
    action: Selector,
    keyEquivalent: String = ""
  ) -> NSMenuItem {
    let item = NSMenuItem(
      title: title,
      action: action,
      keyEquivalent: keyEquivalent
    )
    item.target = self
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
  private func quit() {
    Task {
      await actions?.quit()
    }
  }
}
