import AppKit

@MainActor
protocol VoiceSettingsPresenting: AnyObject {
  func show(relativeTo positioningView: NSView)
}

@MainActor
final class VoiceSettingsPopoverController:
  NSObject,
  VoiceSettingsPresenting
{
  private struct VoiceOption {
    let identifier: String
    let title: String
  }

  private static let contentSize = NSSize(width: 360, height: 270)
  private static let voiceOptions = [
    VoiceOption(identifier: "alloy", title: "Alloy"),
    VoiceOption(identifier: "ash", title: "Ash"),
    VoiceOption(identifier: "ballad", title: "Ballad"),
    VoiceOption(identifier: "coral", title: "Coral"),
    VoiceOption(identifier: "echo", title: "Echo"),
    VoiceOption(identifier: "sage", title: "Sage"),
    VoiceOption(identifier: "shimmer", title: "Shimmer"),
    VoiceOption(identifier: "verse", title: "Verse"),
    VoiceOption(identifier: "marin", title: "Marin"),
    VoiceOption(identifier: "cedar", title: "Cedar"),
  ]

  let popover: NSPopover

  private let preferencesStore: any InterfacePreferencesStoring
  private let openSoundSettings: @MainActor () -> Void
  private let voicePicker = NSPopUpButton()
  private let modelLabel = NSTextField(
    labelWithString: "Model: gpt-realtime-2.1"
  )
  private let statusLabel = NSTextField(wrappingLabelWithString: "")
  private let audioPolicyLabel = NSTextField(
    wrappingLabelWithString:
      "Audio input and output follow macOS System Settings."
  )
  private let soundSettingsButton = NSButton()

  init(
    preferencesStore: any InterfacePreferencesStoring,
    openSoundSettings: @escaping @MainActor () -> Void
  ) {
    self.preferencesStore = preferencesStore
    self.openSoundSettings = openSoundSettings
    popover = NSPopover()

    super.init()

    configurePopover()
    configureVoicePicker()
    configureModelLabel()
    configureStatusLabel()
    configureAudioPolicyLabel()
    configureSoundSettingsButton()
    installContent()
    render(preferencesStore.load())
  }

  func show(relativeTo positioningView: NSView) {
    render(preferencesStore.load())
    popover.show(
      relativeTo: positioningView.bounds,
      of: positioningView,
      preferredEdge: .minY
    )
  }

  private func configurePopover() {
    popover.behavior = .transient
    popover.animates = false
    popover.contentSize = Self.contentSize
  }

  private func configureVoicePicker() {
    for option in Self.voiceOptions {
      voicePicker.addItem(withTitle: option.title)
      voicePicker.lastItem?.representedObject = option.identifier
    }
    voicePicker.setAccessibilityElement(true)
    voicePicker.setAccessibilityLabel("Realtime voice")
    voicePicker.setAccessibilityIdentifier("settings.voice.selection")
    voicePicker.target = self
    voicePicker.action = #selector(selectVoice)
  }

  private func configureModelLabel() {
    modelLabel.font = .systemFont(ofSize: 12)
    modelLabel.textColor = .secondaryLabelColor
    modelLabel.setAccessibilityElement(true)
    modelLabel.setAccessibilityRole(.staticText)
    modelLabel.setAccessibilityLabel("Realtime model")
    modelLabel.setAccessibilityIdentifier("settings.voice.model")
  }

  private func configureStatusLabel() {
    statusLabel.font = .systemFont(ofSize: 12)
    statusLabel.textColor = .secondaryLabelColor
    statusLabel.maximumNumberOfLines = 2
    statusLabel.stringValue = "Changes apply to your next Summon."
    statusLabel.setAccessibilityElement(true)
    statusLabel.setAccessibilityRole(.staticText)
    statusLabel.setAccessibilityLabel("Voice settings status")
    statusLabel.setAccessibilityValue(statusLabel.stringValue)
    statusLabel.setAccessibilityIdentifier("settings.voice.status")
  }

  private func configureAudioPolicyLabel() {
    audioPolicyLabel.font = .systemFont(ofSize: 12)
    audioPolicyLabel.textColor = .secondaryLabelColor
    audioPolicyLabel.maximumNumberOfLines = 2
    audioPolicyLabel.setAccessibilityElement(true)
    audioPolicyLabel.setAccessibilityRole(.staticText)
    audioPolicyLabel.setAccessibilityLabel("System audio policy")
    audioPolicyLabel.setAccessibilityIdentifier(
      "settings.voice.audio-policy"
    )
  }

  private func configureSoundSettingsButton() {
    soundSettingsButton.title = "Open Sound Settings…"
    soundSettingsButton.bezelStyle = .rounded
    soundSettingsButton.controlSize = .regular
    soundSettingsButton.target = self
    soundSettingsButton.action = #selector(openSystemSoundSettings)
    soundSettingsButton.setAccessibilityElement(true)
    soundSettingsButton.setAccessibilityLabel(
      "Open macOS Sound Settings"
    )
    soundSettingsButton.setAccessibilityIdentifier(
      "settings.voice.sound-settings"
    )
  }

  private func installContent() {
    let rootView = NSView(
      frame: NSRect(origin: .zero, size: Self.contentSize)
    )
    rootView.setAccessibilityElement(true)
    rootView.setAccessibilityRole(.group)
    rootView.setAccessibilityLabel("Voice and system audio settings")

    let titleLabel = NSTextField(
      labelWithString: "Voice Settings"
    )
    titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    titleLabel.frame = NSRect(x: 16, y: 234, width: 328, height: 20)

    let voiceLabel = NSTextField(labelWithString: "Voice")
    voiceLabel.frame = NSRect(x: 16, y: 197, width: 64, height: 20)
    voicePicker.frame = NSRect(x: 80, y: 191, width: 150, height: 28)
    modelLabel.frame = NSRect(x: 16, y: 168, width: 328, height: 20)
    statusLabel.frame = NSRect(x: 16, y: 132, width: 328, height: 32)
    audioPolicyLabel.frame = NSRect(x: 16, y: 78, width: 328, height: 42)
    soundSettingsButton.frame = NSRect(
      x: 16,
      y: 32,
      width: 176,
      height: 30
    )

    rootView.addSubview(titleLabel)
    rootView.addSubview(voiceLabel)
    rootView.addSubview(voicePicker)
    rootView.addSubview(modelLabel)
    rootView.addSubview(statusLabel)
    rootView.addSubview(audioPolicyLabel)
    rootView.addSubview(soundSettingsButton)

    let contentViewController = NSViewController()
    contentViewController.view = rootView
    popover.contentViewController = contentViewController
  }

  private func render(_ preferences: LocalInterfacePreferences) {
    let selectedVoice = preferences.voiceIdentifier ?? "marin"
    guard
      let index = Self.voiceOptions.firstIndex(where: {
        $0.identifier == selectedVoice
      })
    else {
      voicePicker.selectItem(
        at: Self.voiceOptions.firstIndex(where: {
          $0.identifier == "marin"
        }) ?? 0
      )
      return
    }

    voicePicker.selectItem(at: index)
  }

  @objc
  private func selectVoice() {
    guard
      let identifier =
        voicePicker.selectedItem?.representedObject as? String
    else {
      return
    }

    let preferences = preferencesStore.load()
    let updated = LocalInterfacePreferences(
      avatar: preferences.avatar,
      presence: preferences.presence,
      voiceIdentifier: identifier,
      modelIdentifier: preferences.modelIdentifier,
      volume: preferences.volume,
      shortcut: preferences.shortcut,
      parkedPosition: preferences.parkedPosition
    )

    do {
      try preferencesStore.save(updated)
      renderStatus("Voice saved. Applies to your next Summon.")
    } catch {
      render(preferences)
      renderStatus("Voice could not be saved.")
    }
  }

  private func renderStatus(_ message: String) {
    statusLabel.stringValue = message
    statusLabel.setAccessibilityValue(message)
  }

  @objc
  private func openSystemSoundSettings() {
    openSoundSettings()
  }
}
