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
    runtime.emit(snapshot())
    await drainTasks()

    await actions.summonOrEnd()
    await actions.park()
    await actions.hideOrShow()
    await actions.selectAvatar(.athena)
    await actions.moveToCurrentDisplay()

    runtime.emit(
      snapshot(
        avatar: .athena,
        voice: .listening,
        bubble: .listening
      )
    )
    await drainTasks()
    await actions.summonOrEnd()

    runtime.emit(
      snapshot(
        avatar: .athena,
        voice: .muted,
        bubble: .muted
      )
    )
    await drainTasks()
    await actions.muteOrUnmute()
    await actions.quit()

    #expect(
      runtime.commands == [
        .launch,
        .summon(.statusMenu),
        .setPresence(.parked),
        .setPresence(.hidden),
        .selectAvatar(.athena),
        .moveToCurrentDisplay,
        .endConversation,
        .setMuted(false),
        .endConversation,
      ]
    )
    #expect(application.terminationCount == 1)
  }

  @Test
  func menuRendersSnapshotsAndRetriesOnlyAfterAnError() async throws {
    let runtime = RecordingRuntime()
    let statusMenu = RecordingStatusMenu()
    let coordinator = ApplicationCoordinator(
      runtime: runtime,
      statusMenu: statusMenu,
      application: RecordingApplication()
    )

    await coordinator.start()
    let actions = try #require(statusMenu.actions)
    let failure = CompanionFailure(
      kind: .network,
      message: "Connection lost. Retry when ready."
    )
    let failed = snapshot(
      presence: .parked,
      voice: .error(failure),
      bubble: .error(failure.message),
      recoverableError: failure
    )

    runtime.emit(failed)
    await drainTasks()

    #expect(statusMenu.renderedSnapshots == [failed])

    await actions.summonOrEnd()
    await actions.roam()
    await actions.muteOrUnmute()

    #expect(
      runtime.commands == [
        .launch,
        .retryConversation,
        .setPresence(.roaming),
      ]
    )
  }

  private func snapshot(
    avatar: CompanionAvatar = .orion,
    presence: PresenceState = .roaming,
    voice: VoiceSessionState = .idle,
    bubble: BubbleState = .hidden,
    recoverableError: CompanionFailure? = nil
  ) -> CompanionSnapshot {
    CompanionSnapshot(
      avatar: avatar,
      basePresence: presence,
      isVisible: presence != .hidden || voice != .idle,
      placement: CompanionPlacement(
        displayID: "main",
        position: StagePoint(x: 720, y: 450)
      ),
      voice: voice,
      bubble: bubble,
      waveformEnergy: 0,
      recoverableError: recoverableError
    )
  }

  private func drainTasks() async {
    for _ in 0..<20 {
      await Task.yield()
    }
  }
}

@MainActor
private final class RecordingRuntime: CompanionCommandRouting {
  let snapshots: AsyncStream<CompanionSnapshot>

  private let continuation: AsyncStream<CompanionSnapshot>.Continuation
  private(set) var commands: [CompanionCommand] = []

  init() {
    let pair = AsyncStream<CompanionSnapshot>.makeStream()
    snapshots = pair.stream
    continuation = pair.continuation
  }

  func send(_ command: CompanionCommand) async {
    commands.append(command)
  }

  func emit(_ snapshot: CompanionSnapshot) {
    continuation.yield(snapshot)
  }
}

@MainActor
private final class RecordingStatusMenu: StatusMenuPresenting {
  private(set) var actions: StatusMenuActions?
  private(set) var installCount = 0
  private(set) var renderedSnapshots: [CompanionSnapshot] = []

  func install(actions: StatusMenuActions) {
    self.actions = actions
    installCount += 1
  }

  func render(_ snapshot: CompanionSnapshot) {
    renderedSnapshots.append(snapshot)
  }
}

@MainActor
private final class RecordingApplication: ApplicationTerminating {
  private(set) var terminationCount = 0

  func terminateApplication() {
    terminationCount += 1
  }
}
