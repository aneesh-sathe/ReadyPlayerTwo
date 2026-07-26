import CompanionRuntime
import Foundation

typealias ReachableParkedPosition = CompanionParkedPosition

struct LocalInterfacePreferences: Codable, Equatable, Sendable {
  let avatar: CompanionAvatar
  let presence: PresenceState
  let voiceIdentifier: String?
  let modelIdentifier: String?
  let volume: Double
  let shortcut: GlobalShortcut
  let parkedPosition: ReachableParkedPosition?

  static let defaults = Self()

  init(
    avatar: CompanionAvatar = .orion,
    presence: PresenceState = .roaming,
    voiceIdentifier: String? = "marin",
    modelIdentifier: String? = "gpt-realtime-2.1",
    volume: Double = 1,
    shortcut: GlobalShortcut = .defaultSummon,
    parkedPosition: ReachableParkedPosition? = nil
  ) {
    self.avatar = avatar
    self.presence = presence
    self.voiceIdentifier = voiceIdentifier
    self.modelIdentifier = modelIdentifier
    self.volume = volume
    self.shortcut = shortcut
    self.parkedPosition = parkedPosition
  }

  var isValid: Bool {
    volume.isFinite
      && (0...1).contains(volume)
      && shortcut.isValid
      && isValidIdentifier(voiceIdentifier)
      && isValidIdentifier(modelIdentifier)
      && (parkedPosition?.isValid ?? true)
  }

  private func isValidIdentifier(_ identifier: String?) -> Bool {
    guard let identifier else {
      return true
    }
    guard !identifier.isEmpty, identifier.count <= 128 else {
      return false
    }

    let lowercased = identifier.lowercased()
    guard
      !lowercased.hasPrefix("sk-"),
      !lowercased.hasPrefix("ek_"),
      !lowercased.hasPrefix("bearer")
    else {
      return false
    }

    let allowed = CharacterSet(
      charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    )
    return identifier.unicodeScalars.allSatisfy(allowed.contains)
  }
}

enum InterfacePreferencesStoreError: Error, Equatable {
  case invalidPreferences
}

@MainActor
protocol InterfacePreferencesStoring: AnyObject {
  func load() -> LocalInterfacePreferences
  func save(_ preferences: LocalInterfacePreferences) throws
  func clear()
}

/// Stores only the typed interface schema above. It intentionally has no
/// credential, transcript, audio, conversation-text, or Companion Memory
/// fields.
@MainActor
final class UserDefaultsInterfacePreferencesStore:
  InterfacePreferencesStoring
{
  static let storageKey = "ReadyPlayerTwo.LocalInterfacePreferences.v1"

  private let defaults: UserDefaults
  private let decoder = JSONDecoder()
  private let encoder: JSONEncoder

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    self.encoder = encoder
  }

  func load() -> LocalInterfacePreferences {
    guard
      let data = defaults.data(forKey: Self.storageKey),
      let preferences = try? decoder.decode(
        LocalInterfacePreferences.self,
        from: data
      ),
      preferences.isValid
    else {
      return .defaults
    }

    return preferences
  }

  func save(_ preferences: LocalInterfacePreferences) throws {
    guard preferences.isValid else {
      throw InterfacePreferencesStoreError.invalidPreferences
    }

    let data = try encoder.encode(preferences)
    defaults.set(data, forKey: Self.storageKey)
  }

  func clear() {
    defaults.removeObject(forKey: Self.storageKey)
  }
}
