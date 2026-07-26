import AppKit
import CompanionRuntime
import Testing

@testable import ReadyPlayerTwo

@Suite(.serialized)
@MainActor
struct ShortcutSettingsPopoverControllerTests {
  @Test
  func showsCurrentShortcutAndRequiresExplicitRecordingMode() throws {
    let preferences = LocalInterfacePreferences.defaults
    let store = SettingsPreferencesStore(preferences: preferences)
    let registrar = SettingsShortcutRegistrar()
    let shortcutController = GlobalShortcutController(
      registrar: registrar
    )
    _ = shortcutController.activate(preferences.shortcut) {}
    let controller = ShortcutSettingsPopoverController(
      shortcutController: shortcutController,
      availabilityRegistrar: registrar,
      preferencesStore: store,
      onShortcutInvocation: {}
    )
    let rootView = try #require(
      controller.popover.contentViewController?.view
    )
    let current = try #require(
      settingsView(
        in: rootView,
        identifier: "settings.shortcut.current"
      ) as? NSTextField
    )
    let recorder = try #require(
      settingsView(
        in: rootView,
        identifier: "settings.shortcut.recorder"
      )
    )
    let recordButton = try #require(
      settingsView(
        in: rootView,
        identifier: "settings.shortcut.record"
      ) as? NSButton
    )
    let status = try #require(
      settingsView(
        in: rootView,
        identifier: "settings.shortcut.status"
      ) as? NSTextField
    )

    #expect(current.stringValue == "Control + Shift + Space")
    #expect(current.accessibilityLabel() == "Current shortcut")
    #expect(recordButton.title == "Record Shortcut")
    #expect(status.stringValue == "Select Record Shortcut to begin.")

    recorder.keyDown(
      with: try settingsKeyEvent(
        keyCode: 40,
        modifiers: [.command],
        characters: "k"
      )
    )
    #expect(registrar.requestedShortcuts == [.defaultSummon])
    #expect(store.savedPreferences.isEmpty)

    recordButton.performClick(nil)

    #expect(recordButton.title == "Cancel Recording")
    #expect(
      status.stringValue
        == "Press a key with Command, Control, Option, or Shift."
    )
    #expect(recorder.accessibilityValue() as? String == "Recording shortcut")
  }

  @Test
  func invalidKeyDownsStayInRecordingWithoutRegistration() throws {
    let preferences = LocalInterfacePreferences.defaults
    let store = SettingsPreferencesStore(preferences: preferences)
    let registrar = SettingsShortcutRegistrar()
    let shortcutController = GlobalShortcutController(
      registrar: registrar
    )
    _ = shortcutController.activate(preferences.shortcut) {}
    let controller = ShortcutSettingsPopoverController(
      shortcutController: shortcutController,
      availabilityRegistrar: registrar,
      preferencesStore: store,
      onShortcutInvocation: {}
    )
    let rootView = try #require(
      controller.popover.contentViewController?.view
    )
    let recorder = try #require(
      settingsView(
        in: rootView,
        identifier: "settings.shortcut.recorder"
      )
    )
    let recordButton = try #require(
      settingsView(
        in: rootView,
        identifier: "settings.shortcut.record"
      ) as? NSButton
    )
    let status = try #require(
      settingsView(
        in: rootView,
        identifier: "settings.shortcut.status"
      ) as? NSTextField
    )

    recordButton.performClick(nil)

    recorder.keyDown(
      with: try settingsKeyEvent(
        keyCode: 40,
        modifiers: [],
        characters: "k"
      )
    )
    #expect(status.stringValue == "Add at least one modifier.")

    recorder.keyDown(
      with: try settingsKeyEvent(
        keyCode: 53,
        modifiers: [.command],
        characters: "\u{1b}"
      )
    )
    #expect(status.stringValue == "Escape cannot be used as a shortcut.")

    recorder.keyDown(
      with: try settingsKeyEvent(
        keyCode: 55,
        modifiers: [.command],
        characters: ""
      )
    )
    #expect(status.stringValue == "Choose a non-modifier key.")
    #expect(recordButton.title == "Cancel Recording")
    #expect(recorder.accessibilityValue() as? String == "Recording shortcut")
    #expect(registrar.requestedShortcuts == [.defaultSummon])
    #expect(store.savedPreferences.isEmpty)
  }

  @Test
  func acceptedShortcutActivatesAndPersistsEverySafePreference() throws {
    let preferences = LocalInterfacePreferences(
      avatar: .athena,
      presence: .parked,
      voiceIdentifier: "cedar",
      modelIdentifier: "gpt-realtime-2.1",
      volume: 0.42,
      shortcut: .defaultSummon,
      parkedPosition: ReachableParkedPosition(
        displayID: "display-2",
        horizontalFraction: 0.2,
        verticalFraction: 0.8
      )
    )
    let candidate = GlobalShortcut(
      keyCode: 40,
      modifiers: [.command, .option]
    )
    let store = SettingsPreferencesStore(preferences: preferences)
    let registrar = SettingsShortcutRegistrar()
    let shortcutController = GlobalShortcutController(
      registrar: registrar
    )
    _ = shortcutController.activate(preferences.shortcut) {}
    var invocationCount = 0
    let controller = ShortcutSettingsPopoverController(
      shortcutController: shortcutController,
      availabilityRegistrar: registrar,
      preferencesStore: store,
      onShortcutInvocation: { invocationCount += 1 }
    )
    let rootView = try #require(
      controller.popover.contentViewController?.view
    )
    let recorder = try #require(
      settingsView(
        in: rootView,
        identifier: "settings.shortcut.recorder"
      )
    )
    let recordButton = try #require(
      settingsView(
        in: rootView,
        identifier: "settings.shortcut.record"
      ) as? NSButton
    )
    let current = try #require(
      settingsView(
        in: rootView,
        identifier: "settings.shortcut.current"
      ) as? NSTextField
    )
    let status = try #require(
      settingsView(
        in: rootView,
        identifier: "settings.shortcut.status"
      ) as? NSTextField
    )

    recordButton.performClick(nil)
    recorder.keyDown(
      with: try settingsKeyEvent(
        keyCode: 40,
        modifiers: [.command, .option],
        characters: "k"
      )
    )

    let saved = try #require(store.savedPreferences.first)
    #expect(store.savedPreferences.count == 1)
    #expect(
      saved
        == LocalInterfacePreferences(
          avatar: .athena,
          presence: .parked,
          voiceIdentifier: "cedar",
          modelIdentifier: "gpt-realtime-2.1",
          volume: 0.42,
          shortcut: candidate,
          parkedPosition: ReachableParkedPosition(
            displayID: "display-2",
            horizontalFraction: 0.2,
            verticalFraction: 0.8
          )
        )
    )
    #expect(shortcutController.state == .registered(candidate))
    #expect(registrar.activeShortcuts == [candidate])
    #expect(
      registrar.requestedShortcuts
        == [.defaultSummon, candidate, candidate]
    )
    #expect(current.stringValue == "Option + Command + K")
    #expect(status.stringValue == "Shortcut saved.")
    #expect(recordButton.title == "Record Shortcut")

    registrar.invoke(candidate)
    #expect(invocationCount == 1)
  }

  @Test
  func conflictingShortcutPreservesTheWorkingRegistration() throws {
    let preferences = LocalInterfacePreferences.defaults
    let candidate = GlobalShortcut(
      keyCode: 40,
      modifiers: [.command, .option]
    )
    let store = SettingsPreferencesStore(preferences: preferences)
    let registrar = SettingsShortcutRegistrar(
      conflictingShortcuts: [candidate]
    )
    let shortcutController = GlobalShortcutController(
      registrar: registrar
    )
    _ = shortcutController.activate(preferences.shortcut) {}
    let controller = ShortcutSettingsPopoverController(
      shortcutController: shortcutController,
      availabilityRegistrar: registrar,
      preferencesStore: store,
      onShortcutInvocation: {}
    )
    let rootView = try #require(
      controller.popover.contentViewController?.view
    )
    let recorder = try #require(
      settingsView(
        in: rootView,
        identifier: "settings.shortcut.recorder"
      )
    )
    let recordButton = try #require(
      settingsView(
        in: rootView,
        identifier: "settings.shortcut.record"
      ) as? NSButton
    )
    let status = try #require(
      settingsView(
        in: rootView,
        identifier: "settings.shortcut.status"
      ) as? NSTextField
    )

    recordButton.performClick(nil)
    recorder.keyDown(
      with: try settingsKeyEvent(
        keyCode: 40,
        modifiers: [.command, .option],
        characters: "k"
      )
    )

    #expect(
      shortcutController.state
        == .registered(.defaultSummon)
    )
    #expect(registrar.activeShortcuts == [.defaultSummon])
    #expect(
      status.stringValue
        == "That shortcut is already in use. Try another."
    )
    #expect(recordButton.title == "Cancel Recording")
    #expect(store.savedPreferences.isEmpty)
  }
}

@MainActor
private final class SettingsPreferencesStore: InterfacePreferencesStoring {
  private(set) var preferences: LocalInterfacePreferences
  private(set) var savedPreferences: [LocalInterfacePreferences] = []

  init(preferences: LocalInterfacePreferences) {
    self.preferences = preferences
  }

  func load() -> LocalInterfacePreferences {
    preferences
  }

  func save(_ preferences: LocalInterfacePreferences) throws {
    self.preferences = preferences
    savedPreferences.append(preferences)
  }

  func clear() {}
}

@MainActor
private final class SettingsShortcutRegistrar: GlobalShortcutRegistering {
  private struct Entry {
    let shortcut: GlobalShortcut
    let invocation: @MainActor () -> Void
  }

  private(set) var requestedShortcuts: [GlobalShortcut] = []
  private let conflictingShortcuts: [GlobalShortcut]
  private var entries: [Int: Entry] = [:]
  private var nextIdentifier = 1

  init(conflictingShortcuts: [GlobalShortcut] = []) {
    self.conflictingShortcuts = conflictingShortcuts
  }

  var activeShortcuts: [GlobalShortcut] {
    entries.values.map(\.shortcut)
  }

  func register(
    _ shortcut: GlobalShortcut,
    onInvocation: @escaping @MainActor () -> Void
  ) throws -> any GlobalShortcutRegistration {
    requestedShortcuts.append(shortcut)
    if conflictingShortcuts.contains(shortcut) {
      throw GlobalShortcutRegistrationError.conflict
    }
    let identifier = nextIdentifier
    nextIdentifier += 1
    entries[identifier] = Entry(
      shortcut: shortcut,
      invocation: onInvocation
    )
    return SettingsShortcutRegistration { [weak self] in
      self?.entries.removeValue(forKey: identifier)
    }
  }

  func invoke(_ shortcut: GlobalShortcut) {
    entries.values.first(where: { $0.shortcut == shortcut })?
      .invocation()
  }
}

@MainActor
private final class SettingsShortcutRegistration:
  GlobalShortcutRegistration
{
  private let onUnregister: @MainActor () -> Void
  private var isRegistered = true

  init(onUnregister: @escaping @MainActor () -> Void) {
    self.onUnregister = onUnregister
  }

  func unregister() {
    guard isRegistered else {
      return
    }

    isRegistered = false
    onUnregister()
  }
}

@MainActor
private func settingsView(
  in view: NSView,
  identifier: String
) -> NSView? {
  if view.accessibilityIdentifier() == identifier {
    return view
  }

  for subview in view.subviews {
    if let match = settingsView(in: subview, identifier: identifier) {
      return match
    }
  }
  return nil
}

private func settingsKeyEvent(
  keyCode: UInt16,
  modifiers: NSEvent.ModifierFlags,
  characters: String
) throws -> NSEvent {
  try #require(
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: modifiers,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: characters,
      charactersIgnoringModifiers: characters,
      isARepeat: false,
      keyCode: keyCode
    )
  )
}
