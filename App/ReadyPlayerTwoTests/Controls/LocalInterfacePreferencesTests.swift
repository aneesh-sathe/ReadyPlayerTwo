import CompanionRuntime
import Foundation
import Testing
@testable import ReadyPlayerTwo

@Suite(.serialized)
@MainActor
struct LocalInterfacePreferencesTests {
  @Test
  func missingPreferencesLoadTheSafeDefaults() {
    withStore { store, _ in
      let preferences = store.load()

      #expect(preferences.avatar == .orion)
      #expect(preferences.presence == .roaming)
      #expect(preferences.voiceIdentifier == "marin")
      #expect(preferences.modelIdentifier == "gpt-realtime-2.1")
      #expect(preferences.volume == 1)
      #expect(preferences.shortcut.keyCode == 49)
      #expect(preferences.shortcut.modifiers == [.control, .shift])
      #expect(preferences.parkedPosition == nil)
    }
  }

  @Test
  func parkedPositionResolvesInsideTheReachableInset() {
    let position = ReachableParkedPosition(
      displayID: "main",
      horizontalFraction: 0,
      verticalFraction: 1
    )
    let frame = StageRect(
      origin: StagePoint(x: -100, y: 20),
      size: StageSize(width: 1_000, height: 600)
    )

    #expect(position.point(in: frame, inset: 64) == StagePoint(x: -36, y: 556))
  }

  @Test
  func parkedPositionNormalizesAReachableStagePoint() throws {
    let frame = StageRect(
      origin: StagePoint(x: -100, y: 20),
      size: StageSize(width: 1_000, height: 600)
    )

    let position = try #require(
      ReachableParkedPosition(
        displayID: "main",
        point: StagePoint(x: 182, y: 320),
        in: frame,
        inset: 64
      )
    )

    #expect(position.horizontalFraction == 0.25)
    #expect(position.verticalFraction == 0.5)
    #expect(
      position.point(in: frame, inset: 64)
        == StagePoint(x: 182, y: 320)
    )
  }

  @Test
  func allowedInterfacePreferencesPersistAndReload() throws {
    try withStore { store, defaults in
      let preferences = LocalInterfacePreferences(
        avatar: .athena,
        presence: .parked,
        voiceIdentifier: "marin",
        modelIdentifier: "gpt-realtime-2.1",
        volume: 0.65,
        shortcut: GlobalShortcut(
          keyCode: 1,
          modifiers: [.command, .shift]
        ),
        parkedPosition: ReachableParkedPosition(
          displayID: "display-2",
          horizontalFraction: 0.25,
          verticalFraction: 0.75
        )
      )

      try store.save(preferences)

      #expect(store.load() == preferences)

      let data = try #require(
        defaults.data(forKey: UserDefaultsInterfacePreferencesStore.storageKey)
      )
      let json = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
      )
      #expect(
        Set(json.keys)
          == Set([
            "avatar",
            "modelIdentifier",
            "parkedPosition",
            "presence",
            "shortcut",
            "voiceIdentifier",
            "volume",
          ])
      )
      #expect(
        Set(json.keys).isDisjoint(
          with: [
            "apiKey",
            "audio",
            "conversation",
            "credentials",
            "memory",
            "transcript",
          ]
        )
      )
    }
  }

  @Test
  func corruptOrInvalidStoredDataFallsBackToDefaults() throws {
    try withStore { store, defaults in
      defaults.set(
        Data("not-json".utf8),
        forKey: UserDefaultsInterfacePreferencesStore.storageKey
      )
      #expect(store.load() == .defaults)

      let invalid = try JSONSerialization.data(
        withJSONObject: [
          "avatar": "athena",
          "modelIdentifier": "gpt-realtime-2.1",
          "presence": "parked",
          "shortcut": [
            "keyCode": 49,
            "modifiers": 4_608,
          ],
          "voiceIdentifier": "marin",
          "volume": 2,
        ]
      )
      defaults.set(
        invalid,
        forKey: UserDefaultsInterfacePreferencesStore.storageKey
      )

      #expect(store.load() == .defaults)
    }
  }

  @Test
  func sensitiveOrConversationalIdentifiersAreRejected() {
    withStore { store, defaults in
      let sensitivePreferences = LocalInterfacePreferences(
        voiceIdentifier: "sk-test",
        modelIdentifier: "conversation text must not be stored"
      )

      do {
        try store.save(sensitivePreferences)
        Issue.record("Expected sensitive preferences to be rejected.")
      } catch let error as InterfacePreferencesStoreError {
        #expect(error == .invalidPreferences)
      } catch {
        Issue.record("Unexpected error: \(type(of: error))")
      }

      #expect(
        defaults.data(
          forKey: UserDefaultsInterfacePreferencesStore.storageKey
        ) == nil
      )
    }
  }

  private func withStore(
    _ body: (
      UserDefaultsInterfacePreferencesStore,
      UserDefaults
    ) throws -> Void
  ) rethrows {
    let suiteName = "ReadyPlayerTwoTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }

    try body(
      UserDefaultsInterfacePreferencesStore(defaults: defaults),
      defaults
    )
  }
}
