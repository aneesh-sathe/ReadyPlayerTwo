import CompanionRuntime
import Testing
@testable import ReadyPlayerTwo

@Suite(.serialized)
@MainActor
struct ApplicationCoordinatorTests {
  @Test
  func launchInstallsOneMenuAndStartsOneRuntime() async {
    let runtime = RecordingRuntime()
    let statusMenu = RecordingStatusMenu()
    let application = RecordingApplication()
    let coordinator = ApplicationCoordinator(
      runtime: runtime,
      statusMenu: statusMenu,
      application: application
    )

    await coordinator.start()
    await coordinator.start()

    #expect(statusMenu.installCount == 1)
    #expect(runtime.commands == [.launch])
    #expect(application.terminationCount == 0)
  }

  @Test
  func menuActionsRouteThroughRuntimeBeforeTermination() async throws {
    let runtime = RecordingRuntime()
    let statusMenu = RecordingStatusMenu()
    let application = RecordingApplication()
    let coordinator = ApplicationCoordinator(
      runtime: runtime,
      statusMenu: statusMenu,
      application: application
    )

    await coordinator.start()

    let actions = try #require(statusMenu.actions)
    await actions.summon()
    await actions.park()
    await actions.hide()
    await actions.quit()

    #expect(
      runtime.commands == [
        .launch,
        .summon(.statusMenu),
        .setPresence(.parked),
        .setPresence(.hidden),
        .endConversation,
      ]
    )
    #expect(application.terminationCount == 1)
  }
}

@MainActor
private final class RecordingRuntime: CompanionCommandRouting {
  private(set) var commands: [CompanionCommand] = []

  func send(_ command: CompanionCommand) async {
    commands.append(command)
  }
}

@MainActor
private final class RecordingStatusMenu: StatusMenuPresenting {
  private(set) var actions: StatusMenuActions?
  private(set) var installCount = 0

  func install(actions: StatusMenuActions) {
    self.actions = actions
    installCount += 1
  }
}

@MainActor
private final class RecordingApplication: ApplicationTerminating {
  private(set) var terminationCount = 0

  func terminateApplication() {
    terminationCount += 1
  }
}
