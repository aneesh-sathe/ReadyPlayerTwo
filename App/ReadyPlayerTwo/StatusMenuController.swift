import AppKit

@MainActor
final class StatusMenuController: NSObject, StatusMenuPresenting {
  private var actions: StatusMenuActions?
  private var statusItem: NSStatusItem?

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
    menu.addItem(
      NSMenuItem(
        title: "Summon",
        action: #selector(summon),
        keyEquivalent: ""
      )
    )
    menu.addItem(
      NSMenuItem(
        title: "Park",
        action: #selector(park),
        keyEquivalent: ""
      )
    )
    menu.addItem(
      NSMenuItem(
        title: "Hide",
        action: #selector(hide),
        keyEquivalent: ""
      )
    )
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(
        title: "Quit ReadyPlayerTwo",
        action: #selector(quit),
        keyEquivalent: "q"
      )
    )

    for item in menu.items where item.action != nil {
      item.target = self
    }

    statusItem.menu = menu
    self.statusItem = statusItem
  }

  @objc
  private func summon() {
    Task {
      await actions?.summon()
    }
  }

  @objc
  private func park() {
    Task {
      await actions?.park()
    }
  }

  @objc
  private func hide() {
    Task {
      await actions?.hide()
    }
  }

  @objc
  private func quit() {
    Task {
      await actions?.quit()
    }
  }
}
