import AppKit
import Carbon

@MainActor
final class ShortcutSettingsPopoverController: NSObject {
  private static let contentSize = NSSize(width: 360, height: 176)

  let popover: NSPopover

  private let shortcutController: GlobalShortcutController
  private let availabilityRegistrar: any GlobalShortcutRegistering
  private let preferencesStore: any InterfacePreferencesStoring
  private let onShortcutInvocation: @MainActor () -> Void
  private let currentLabel = NSTextField(labelWithString: "")
  private let recorderView = LocalShortcutRecorderView()
  private let recordButton = NSButton()
  private let statusLabel = NSTextField(wrappingLabelWithString: "")
  private var preferences: LocalInterfacePreferences

  init(
    shortcutController: GlobalShortcutController,
    availabilityRegistrar: any GlobalShortcutRegistering,
    preferencesStore: any InterfacePreferencesStoring,
    onShortcutInvocation: @escaping @MainActor () -> Void
  ) {
    self.shortcutController = shortcutController
    self.availabilityRegistrar = availabilityRegistrar
    self.preferencesStore = preferencesStore
    self.onShortcutInvocation = onShortcutInvocation
    preferences = preferencesStore.load()
    popover = NSPopover()

    super.init()

    configurePopover()
    configureCurrentLabel()
    configureRecorder()
    configureRecordButton()
    configureStatusLabel()
    installContent()
    renderIdle()
  }

  @objc
  private func toggleRecording() {
    if recorderView.isRecording {
      renderIdle()
      recordButton.window?.makeFirstResponder(recordButton)
    } else {
      recorderView.isRecording = true
      recordButton.title = "Cancel Recording"
      recordButton.setAccessibilityLabel("Cancel shortcut recording")
      statusLabel.stringValue =
        "Press a key with Command, Control, Option, or Shift."
      statusLabel.setAccessibilityValue(statusLabel.stringValue)
      recorderView.window?.makeFirstResponder(recorderView)
    }
  }

  private func configurePopover() {
    popover.behavior = .transient
    popover.animates = false
    popover.contentSize = Self.contentSize
  }

  private func configureCurrentLabel() {
    currentLabel.font = .monospacedSystemFont(
      ofSize: 15,
      weight: .semibold
    )
    currentLabel.alignment = .center
    currentLabel.setAccessibilityElement(true)
    currentLabel.setAccessibilityRole(.staticText)
    currentLabel.setAccessibilityLabel("Current shortcut")
    currentLabel.setAccessibilityIdentifier("settings.shortcut.current")
  }

  private func configureRecorder() {
    recorderView.setAccessibilityIdentifier("settings.shortcut.recorder")
    recorderView.onKeyDown = { [weak self] event in
      self?.capture(event)
    }
  }

  private func configureRecordButton() {
    recordButton.bezelStyle = .rounded
    recordButton.controlSize = .regular
    recordButton.target = self
    recordButton.action = #selector(toggleRecording)
    recordButton.keyEquivalent = "\r"
    recordButton.keyEquivalentModifierMask = []
    recordButton.setAccessibilityElement(true)
    recordButton.setAccessibilityIdentifier("settings.shortcut.record")
  }

  private func configureStatusLabel() {
    statusLabel.font = .systemFont(ofSize: 12)
    statusLabel.textColor = .secondaryLabelColor
    statusLabel.maximumNumberOfLines = 2
    statusLabel.setAccessibilityElement(true)
    statusLabel.setAccessibilityRole(.staticText)
    statusLabel.setAccessibilityLabel("Shortcut recording status")
    statusLabel.setAccessibilityIdentifier("settings.shortcut.status")
  }

  private func installContent() {
    let rootView = NSView(
      frame: NSRect(origin: .zero, size: Self.contentSize)
    )
    rootView.setAccessibilityElement(true)
    rootView.setAccessibilityRole(.group)
    rootView.setAccessibilityLabel("Keyboard shortcut settings")

    let titleLabel = NSTextField(
      labelWithString: "Summon Shortcut"
    )
    titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    titleLabel.frame = NSRect(x: 16, y: 142, width: 328, height: 20)

    currentLabel.frame = NSRect(x: 8, y: 7, width: 312, height: 24)
    recorderView.frame = NSRect(x: 16, y: 98, width: 328, height: 38)
    recordButton.frame = NSRect(x: 16, y: 57, width: 150, height: 30)
    statusLabel.frame = NSRect(x: 16, y: 12, width: 328, height: 36)

    rootView.addSubview(titleLabel)
    rootView.addSubview(recorderView)
    recorderView.addSubview(currentLabel)
    rootView.addSubview(recordButton)
    rootView.addSubview(statusLabel)

    let contentViewController = NSViewController()
    contentViewController.view = rootView
    popover.contentViewController = contentViewController
  }

  private func renderIdle(
    status: String = "Select Record Shortcut to begin."
  ) {
    recorderView.isRecording = false
    currentLabel.stringValue =
      ShortcutDisplayName(
        shortcut: preferences.shortcut
      ).description
    currentLabel.setAccessibilityValue(currentLabel.stringValue)
    recorderView.setAccessibilityValue(
      "Current shortcut: \(currentLabel.stringValue)"
    )
    recordButton.title = "Record Shortcut"
    recordButton.setAccessibilityLabel("Record keyboard shortcut")
    statusLabel.stringValue = status
    statusLabel.setAccessibilityValue(statusLabel.stringValue)
  }

  private func capture(_ event: NSEvent) {
    if Int(event.keyCode) == kVK_Escape {
      renderRecordingStatus("Escape cannot be used as a shortcut.")
      return
    }
    if Self.isModifierKey(event.keyCode) {
      renderRecordingStatus("Choose a non-modifier key.")
      return
    }

    let modifiers = ShortcutModifiers(
      eventModifierFlags: event.modifierFlags
    )
    guard !modifiers.isEmpty else {
      renderRecordingStatus("Add at least one modifier.")
      return
    }

    let candidate = GlobalShortcut(
      keyCode: UInt32(event.keyCode),
      modifiers: modifiers
    )
    guard candidate.isValid else {
      renderRecordingStatus("That shortcut is not supported.")
      return
    }

    accept(candidate)
  }

  private func accept(_ candidate: GlobalShortcut) {
    guard candidate != preferences.shortcut else {
      renderIdle(status: "Shortcut unchanged.")
      return
    }

    do {
      let probe = try availabilityRegistrar.register(
        candidate,
        onInvocation: {}
      )
      probe.unregister()
    } catch GlobalShortcutRegistrationError.conflict {
      renderRecordingStatus(
        "That shortcut is already in use. Try another."
      )
      return
    } catch {
      renderRecordingStatus(
        "That shortcut could not be registered. Try another."
      )
      return
    }

    let previous = preferences.shortcut
    let activation = shortcutController.activate(
      candidate,
      onInvocation: onShortcutInvocation
    )
    guard activation == .registered(candidate) else {
      _ = shortcutController.activate(
        previous,
        onInvocation: onShortcutInvocation
      )
      renderRecordingStatus(
        "That shortcut became unavailable. Try another."
      )
      return
    }

    let updated = LocalInterfacePreferences(
      avatar: preferences.avatar,
      presence: preferences.presence,
      voiceIdentifier: preferences.voiceIdentifier,
      modelIdentifier: preferences.modelIdentifier,
      volume: preferences.volume,
      shortcut: candidate,
      parkedPosition: preferences.parkedPosition
    )

    do {
      try preferencesStore.save(updated)
    } catch {
      _ = shortcutController.activate(
        previous,
        onInvocation: onShortcutInvocation
      )
      renderRecordingStatus(
        "The shortcut could not be saved. The previous shortcut is active."
      )
      return
    }

    preferences = updated
    renderIdle(status: "Shortcut saved.")
  }

  private func renderRecordingStatus(_ message: String) {
    statusLabel.stringValue = message
    statusLabel.setAccessibilityValue(message)
  }

  private static func isModifierKey(_ keyCode: UInt16) -> Bool {
    switch Int(keyCode) {
    case kVK_Command,
      kVK_RightCommand,
      kVK_Shift,
      kVK_RightShift,
      kVK_Option,
      kVK_RightOption,
      kVK_Control,
      kVK_RightControl,
      kVK_CapsLock,
      kVK_Function:
      true
    default:
      false
    }
  }
}

@MainActor
private final class LocalShortcutRecorderView: NSView {
  var onKeyDown: (@MainActor (NSEvent) -> Void)?

  var isRecording = false {
    didSet {
      updateAppearance()
    }
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  override func keyDown(with event: NSEvent) {
    guard isRecording else {
      return
    }

    onKeyDown?(event)
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    wantsLayer = true
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("Shortcut recorder")
    focusRingType = .exterior
    updateAppearance()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  private func updateAppearance() {
    layer?.cornerRadius = 8
    layer?.borderWidth = isRecording ? 2 : 1
    layer?.borderColor =
      (isRecording ? NSColor.controlAccentColor : .separatorColor).cgColor
    setAccessibilityValue(
      isRecording ? "Recording shortcut" : "Not recording"
    )
    needsDisplay = true
  }
}

private extension ShortcutModifiers {
  init(eventModifierFlags: NSEvent.ModifierFlags) {
    var modifiers: ShortcutModifiers = []
    if eventModifierFlags.contains(.command) {
      modifiers.insert(.command)
    }
    if eventModifierFlags.contains(.control) {
      modifiers.insert(.control)
    }
    if eventModifierFlags.contains(.option) {
      modifiers.insert(.option)
    }
    if eventModifierFlags.contains(.shift) {
      modifiers.insert(.shift)
    }
    self = modifiers
  }
}

private struct ShortcutDisplayName {
  private static let keyNames: [UInt32: String] = [
    UInt32(kVK_ANSI_A): "A",
    UInt32(kVK_ANSI_B): "B",
    UInt32(kVK_ANSI_C): "C",
    UInt32(kVK_ANSI_D): "D",
    UInt32(kVK_ANSI_E): "E",
    UInt32(kVK_ANSI_F): "F",
    UInt32(kVK_ANSI_G): "G",
    UInt32(kVK_ANSI_H): "H",
    UInt32(kVK_ANSI_I): "I",
    UInt32(kVK_ANSI_J): "J",
    UInt32(kVK_ANSI_K): "K",
    UInt32(kVK_ANSI_L): "L",
    UInt32(kVK_ANSI_M): "M",
    UInt32(kVK_ANSI_N): "N",
    UInt32(kVK_ANSI_O): "O",
    UInt32(kVK_ANSI_P): "P",
    UInt32(kVK_ANSI_Q): "Q",
    UInt32(kVK_ANSI_R): "R",
    UInt32(kVK_ANSI_S): "S",
    UInt32(kVK_ANSI_T): "T",
    UInt32(kVK_ANSI_U): "U",
    UInt32(kVK_ANSI_V): "V",
    UInt32(kVK_ANSI_W): "W",
    UInt32(kVK_ANSI_X): "X",
    UInt32(kVK_ANSI_Y): "Y",
    UInt32(kVK_ANSI_Z): "Z",
    UInt32(kVK_Space): "Space",
    UInt32(kVK_Return): "Return",
    UInt32(kVK_Tab): "Tab",
    UInt32(kVK_LeftArrow): "Left Arrow",
    UInt32(kVK_RightArrow): "Right Arrow",
    UInt32(kVK_UpArrow): "Up Arrow",
    UInt32(kVK_DownArrow): "Down Arrow",
  ]

  let description: String

  init(shortcut: GlobalShortcut) {
    var parts: [String] = []
    if shortcut.modifiers.contains(.control) {
      parts.append("Control")
    }
    if shortcut.modifiers.contains(.option) {
      parts.append("Option")
    }
    if shortcut.modifiers.contains(.shift) {
      parts.append("Shift")
    }
    if shortcut.modifiers.contains(.command) {
      parts.append("Command")
    }

    parts.append(
      Self.keyNames[shortcut.keyCode]
        ?? "Key \(shortcut.keyCode)"
    )
    description = parts.joined(separator: " + ")
  }
}
