import AppKit
import CompanionRuntime

@MainActor
protocol CompanionCommandRouting: AnyObject {
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
  let summon: @MainActor () async -> Void
  let park: @MainActor () async -> Void
  let hide: @MainActor () async -> Void
  let quit: @MainActor () async -> Void
}

@MainActor
protocol StatusMenuPresenting: AnyObject {
  func install(actions: StatusMenuActions)
}

@MainActor
final class ApplicationCoordinator {
  private let runtime: any CompanionCommandRouting
  private let statusMenu: any StatusMenuPresenting
  private let application: any ApplicationTerminating
  private var hasStarted = false

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
        summon: { [weak self] in
          guard let self else {
            return
          }
          await self.runtime.send(.summon(.statusMenu))
        },
        park: { [weak self] in
          guard let self else {
            return
          }
          await self.runtime.send(.setPresence(.parked))
        },
        hide: { [weak self] in
          guard let self else {
            return
          }
          await self.runtime.send(.setPresence(.hidden))
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

    await runtime.send(.launch)
  }
}
