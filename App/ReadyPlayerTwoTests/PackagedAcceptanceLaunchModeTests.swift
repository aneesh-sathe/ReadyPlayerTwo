import Testing

@testable import ReadyPlayerTwo

@Suite(.serialized)
struct PackagedAcceptanceLaunchModeTests {
  @Test
  func packagedAcceptanceRequiresTheExactLaunchArgument() {
    #expect(
      ApplicationLaunchMode.resolve(
        arguments: ["-ReadyPlayerTwoPackagedAcceptance"]
      )
        == .packagedAcceptance
    )
    #expect(
      ApplicationLaunchMode.resolve(
        arguments: ["ReadyPlayerTwoPackagedAcceptance"]
      )
        == .production
    )
    #expect(
      ApplicationLaunchMode.resolve(arguments: [])
        == .production
    )
  }

  @Test
  @MainActor
  func packagedAcceptanceStartsWithCleanIsolatedPreferences() throws {
    let firstStore =
      ApplicationLaunchMode.packagedAcceptance.makePreferencesStore()
    try firstStore.save(
      LocalInterfacePreferences(
        avatar: .athena,
        presence: .hidden
      )
    )

    let nextLaunchStore =
      ApplicationLaunchMode.packagedAcceptance.makePreferencesStore()

    #expect(nextLaunchStore.load() == .defaults)
  }

  @Test
  @MainActor
  func packagedAcceptanceSuppressesNondeterministicSideEffects() async {
    let mode = ApplicationLaunchMode.packagedAcceptance

    #expect(!mode.registersGlobalShortcut)
    #expect(!mode.monitorsPlatformEvents)
    #expect(
      await mode.makeVoiceReadinessChecker().check()
        == .notConfigured
    )
  }

}
