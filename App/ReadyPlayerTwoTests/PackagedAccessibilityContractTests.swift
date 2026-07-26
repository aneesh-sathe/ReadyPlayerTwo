import AppKit
import CompanionRuntime
import Testing

@testable import ReadyPlayerTwo

@Suite(.serialized)
struct PackagedAccessibilityContractTests {
  @Test
  @MainActor
  func statusMenuCommandsHaveStableAccessibilityIdentifiers() throws {
    let controller = StatusMenuController()
    controller.install(actions: inertStatusMenuActions)
    defer {
      controller.uninstall()
    }

    let menu = try #require(controller.installedMenu)
    let identifiers = Set(
      menu.items.compactMap { $0.accessibilityIdentifier() }
    )
    #expect(
      identifiers.isSuperset(
        of: [
          "status.conversation",
          "status.roam",
          "status.park",
          "status.hide-or-show",
          "status.companion",
          "status.quit",
        ]
      )
    )

    let companionMenu = try #require(
      menu.items.first(where: {
        $0.accessibilityIdentifier() == "status.companion"
      })?.submenu
    )
    #expect(
      Set(
        companionMenu.items.compactMap {
          $0.accessibilityIdentifier()
        }
      )
        == [
          "status.avatar.orion",
          "status.avatar.athena",
        ]
    )
  }

  @Test
  @MainActor
  func companionStageExposesItsRenderedAvatarAndPresence() async throws {
    let stage = CompanionStage(bundle: Bundle(for: AppDelegate.self))
    defer {
      stage.panel.orderOut(nil)
    }
    let snapshot = CompanionSnapshot(
      avatar: .athena,
      basePresence: .parked,
      isVisible: true,
      placement: CompanionPlacement(
        displayID: "main",
        position: StagePoint(x: 720, y: 450)
      ),
      voice: .idle,
      bubble: .hidden,
      waveformEnergy: 0,
      recoverableError: nil
    )

    await stage.render(snapshot)

    let rootView = try #require(stage.panel.contentView)
    #expect(
      stage.panel.accessibilityIdentifier()
        == "companion.window"
    )
    #expect(
      rootView.accessibilityIdentifier()
        == "companion.stage"
    )
    #expect(
      rootView.accessibilityValue() as? String
        == "Athena, Parked"
    )
  }

  @MainActor
  private var inertStatusMenuActions: StatusMenuActions {
    StatusMenuActions(
      summonOrEnd: {},
      roam: {},
      park: {},
      hideOrShow: {},
      selectAvatar: { _ in },
      moveToCurrentDisplay: {},
      muteOrUnmute: {},
      quit: {}
    )
  }
}
