import Foundation

enum ApplicationLaunchMode: Equatable {
  case production
  case packagedAcceptance

  private static let packagedAcceptanceArgument =
    "-ReadyPlayerTwoPackagedAcceptance"
  private static let packagedAcceptancePreferencesSuite =
    "com.aneeshsathe.readyplayertwo.packaged-acceptance"

  static func resolve(
    arguments: [String] = ProcessInfo.processInfo.arguments
  ) -> Self {
    #if DEBUG
      arguments.contains(packagedAcceptanceArgument)
        ? .packagedAcceptance
        : .production
    #else
      .production
    #endif
  }

  @MainActor
  func makePreferencesStore()
    -> UserDefaultsInterfacePreferencesStore
  {
    #if DEBUG
      guard self == .packagedAcceptance else {
        return UserDefaultsInterfacePreferencesStore()
      }
      guard
        let defaults = UserDefaults(
          suiteName: Self.packagedAcceptancePreferencesSuite
        )
      else {
        preconditionFailure(
          "The packaged acceptance preferences suite is unavailable."
        )
      }

      defaults.removePersistentDomain(
        forName: Self.packagedAcceptancePreferencesSuite
      )
      return UserDefaultsInterfacePreferencesStore(
        defaults: defaults
      )
    #else
      return UserDefaultsInterfacePreferencesStore()
    #endif
  }

  var registersGlobalShortcut: Bool {
    #if DEBUG
      self == .production
    #else
      true
    #endif
  }

  var monitorsPlatformEvents: Bool {
    #if DEBUG
      self == .production
    #else
      true
    #endif
  }

  func makeVoiceReadinessChecker()
    -> any VoiceReadinessChecking
  {
    #if DEBUG
      if self == .packagedAcceptance {
        return PackagedAcceptanceVoiceReadinessChecker()
      }
    #endif

    return LoopbackVoiceReadinessChecker()
  }
}

private struct PackagedAcceptanceVoiceReadinessChecker:
  VoiceReadinessChecking
{
  func check() async -> VoiceReadiness {
    .notConfigured
  }
}
