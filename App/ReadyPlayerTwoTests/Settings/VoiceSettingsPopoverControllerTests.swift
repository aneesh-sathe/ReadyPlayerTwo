import AppKit
import CompanionRuntime
import Testing

@testable import ReadyPlayerTwo

@Suite(.serialized)
@MainActor
struct VoiceSettingsPopoverControllerTests {
  @Test
  func showsOnlyAllowlistedVoicesAndTheFixedModel() throws {
    let store = VoiceSettingsPreferencesStore(
      preferences: LocalInterfacePreferences(
        voiceIdentifier: "cedar"
      )
    )
    let controller = VoiceSettingsPopoverController(
      preferencesStore: store,
      openSoundSettings: {}
    )
    let rootView = try #require(
      controller.popover.contentViewController?.view
    )
    let voicePicker = try #require(
      voiceSettingsView(
        in: rootView,
        identifier: "settings.voice.selection"
      ) as? NSPopUpButton
    )
    let model = try #require(
      voiceSettingsView(
        in: rootView,
        identifier: "settings.voice.model"
      ) as? NSTextField
    )

    #expect(
      voicePicker.itemArray.compactMap {
        $0.representedObject as? String
      } == [
        "alloy",
        "ash",
        "ballad",
        "coral",
        "echo",
        "sage",
        "shimmer",
        "verse",
        "marin",
        "cedar",
      ]
    )
    #expect(
      voicePicker.selectedItem?.representedObject as? String
        == "cedar"
    )
    #expect(model.stringValue == "Model: gpt-realtime-2.1")
    #expect(
      rootView.accessibilityLabel()
        == "Voice and system audio settings"
    )
  }

  @Test
  func selectingVoicePreservesEveryOtherSafePreference() throws {
    let original = LocalInterfacePreferences(
      avatar: .athena,
      presence: .parked,
      voiceIdentifier: "cedar",
      modelIdentifier: "gpt-realtime-2.1",
      volume: 0.42,
      shortcut: GlobalShortcut(
        keyCode: 40,
        modifiers: [.command, .option]
      ),
      parkedPosition: ReachableParkedPosition(
        displayID: "display-2",
        horizontalFraction: 0.2,
        verticalFraction: 0.8
      )
    )
    let store = VoiceSettingsPreferencesStore(
      preferences: original
    )
    let controller = VoiceSettingsPopoverController(
      preferencesStore: store,
      openSoundSettings: {}
    )
    let rootView = try #require(
      controller.popover.contentViewController?.view
    )
    let voicePicker = try #require(
      voiceSettingsView(
        in: rootView,
        identifier: "settings.voice.selection"
      ) as? NSPopUpButton
    )
    let status = try #require(
      voiceSettingsView(
        in: rootView,
        identifier: "settings.voice.status"
      ) as? NSTextField
    )

    voicePicker.selectItem(withTitle: "Coral")
    let action = try #require(voicePicker.action)
    #expect(
      NSApp.sendAction(
        action,
        to: voicePicker.target,
        from: voicePicker
      )
    )

    #expect(
      store.savedPreferences
        == [
          LocalInterfacePreferences(
            avatar: .athena,
            presence: .parked,
            voiceIdentifier: "coral",
            modelIdentifier: "gpt-realtime-2.1",
            volume: 0.42,
            shortcut: GlobalShortcut(
              keyCode: 40,
              modifiers: [.command, .option]
            ),
            parkedPosition: ReachableParkedPosition(
              displayID: "display-2",
              horizontalFraction: 0.2,
              verticalFraction: 0.8
            )
          )
        ]
    )
    #expect(
      status.stringValue
        == "Voice saved. Applies to your next Summon."
    )
    #expect(
      status.accessibilityValue() as? String
        == status.stringValue
    )
  }

  @Test
  func routesAudioConfigurationToMacOSSoundSettings() throws {
    let store = VoiceSettingsPreferencesStore(
      preferences: .defaults
    )
    var openSoundSettingsCount = 0
    let controller = VoiceSettingsPopoverController(
      preferencesStore: store,
      openSoundSettings: {
        openSoundSettingsCount += 1
      }
    )
    let rootView = try #require(
      controller.popover.contentViewController?.view
    )
    let audioPolicy = try #require(
      voiceSettingsView(
        in: rootView,
        identifier: "settings.voice.audio-policy"
      ) as? NSTextField
    )
    let soundSettingsButton = try #require(
      voiceSettingsView(
        in: rootView,
        identifier: "settings.voice.sound-settings"
      ) as? NSButton
    )

    #expect(
      audioPolicy.stringValue
        == "Audio input and output follow macOS System Settings."
    )
    #expect(
      soundSettingsButton.title == "Open Sound Settings…"
    )
    #expect(
      soundSettingsButton.accessibilityLabel()
        == "Open macOS Sound Settings"
    )
    #expect(
      voiceSettingsViews(in: rootView)
        .compactMap { $0 as? NSSlider }
        .isEmpty
    )

    soundSettingsButton.performClick(nil)

    #expect(openSoundSettingsCount == 1)
  }
}

@MainActor
private final class VoiceSettingsPreferencesStore:
  InterfacePreferencesStoring
{
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
private func voiceSettingsView(
  in view: NSView,
  identifier: String
) -> NSView? {
  if view.accessibilityIdentifier() == identifier {
    return view
  }

  for subview in view.subviews {
    if let match = voiceSettingsView(
      in: subview,
      identifier: identifier
    ) {
      return match
    }
  }
  return nil
}

@MainActor
private func voiceSettingsViews(in view: NSView) -> [NSView] {
  [view] + view.subviews.flatMap(voiceSettingsViews)
}
