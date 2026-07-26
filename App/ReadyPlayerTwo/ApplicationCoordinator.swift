import AppKit
import CompanionRuntime

@MainActor
protocol CompanionCommandRouting: AnyObject {
  var snapshots: AsyncStream<CompanionSnapshot> { get }

  func send(_ command: CompanionCommand) async
}

extension CompanionRuntime: CompanionCommandRouting {}

@MainActor
protocol ApplicationTerminating: AnyObject {
  func terminateApplication()
}

extension NSApplication: ApplicationTerminating {
  func terminateApplication() {
    terminate(nil)
  }
}

@MainActor
struct StatusMenuActions {
  let summonOrEnd: @MainActor () async -> Void
  let roam: @MainActor () async -> Void
  let park: @MainActor () async -> Void
  let hideOrShow: @MainActor () async -> Void
  let selectAvatar: @MainActor (CompanionAvatar) async -> Void
  let moveToCurrentDisplay: @MainActor () async -> Void
  let muteOrUnmute: @MainActor () async -> Void
  let quit: @MainActor () async -> Void
}

@MainActor
protocol StatusMenuPresenting: AnyObject {
  func install(actions: StatusMenuActions)
  func render(_ snapshot: CompanionSnapshot)
}

@MainActor
final class ApplicationCoordinator {
  private let runtime: any CompanionCommandRouting
  private let statusMenu: any StatusMenuPresenting
  private let application: any ApplicationTerminating
  private var hasStarted = false
  private var latestSnapshot: CompanionSnapshot?
  private var snapshotTask: Task<Void, Never>?

  init(
    runtime: any CompanionCommandRouting,
    statusMenu: any StatusMenuPresenting,
    application: any ApplicationTerminating
  ) {
    self.runtime = runtime
    self.statusMenu = statusMenu
    self.application = application
  }

  func start() async {
    guard !hasStarted else {
      return
    }

    hasStarted = true
    statusMenu.install(
      actions: StatusMenuActions(
        summonOrEnd: { [weak self] in
          guard let self else {
            return
          }
          await self.handleConversationAction()
        },
        roam: { [weak self] in
          guard let self else {
            return
          }
          await self.runtime.send(.setPresence(.roaming))
        },
        park: { [weak self] in
          guard let self else {
            return
          }
          await self.runtime.send(.setPresence(.parked))
        },
        hideOrShow: { [weak self] in
          guard let self else {
            return
          }
          let presence: PresenceState =
            self.latestSnapshot?.basePresence == .hidden
            ? .roaming
            : .hidden
          await self.runtime.send(.setPresence(presence))
        },
        selectAvatar: { [weak self] avatar in
          guard let self else {
            return
          }
          await self.runtime.send(.selectAvatar(avatar))
        },
        moveToCurrentDisplay: { [weak self] in
          guard let self else {
            return
          }
          await self.runtime.send(.moveToCurrentDisplay)
        },
        muteOrUnmute: { [weak self] in
          guard let self else {
            return
          }
          await self.handleMuteAction()
        },
        quit: { [weak self] in
          guard let self else {
            return
          }
          await self.runtime.send(.endConversation)
          self.application.terminateApplication()
        }
      )
    )

    let snapshots = runtime.snapshots
    snapshotTask = Task { @MainActor [weak self] in
      for await snapshot in snapshots {
        guard let self else {
          return
        }
        latestSnapshot = snapshot
        statusMenu.render(snapshot)
      }
    }

    await runtime.send(.launch)
  }

  private func handleConversationAction() async {
    guard let latestSnapshot else {
      await runtime.send(.summon(.statusMenu))
      return
    }

    switch latestSnapshot.voice {
    case .idle:
      await runtime.send(.summon(.statusMenu))
    case .error:
      await runtime.send(.retryConversation)
    case .ending:
      return
    case .connecting, .listening, .thinking, .speaking, .muted:
      await runtime.send(.endConversation)
    }
  }

  private func handleMuteAction() async {
    guard let latestSnapshot else {
      return
    }

    switch latestSnapshot.voice {
    case .muted:
      await runtime.send(.setMuted(false))
    case .connecting, .listening, .thinking, .speaking:
      await runtime.send(.setMuted(true))
    case .idle, .error, .ending:
      return
    }
  }
}
