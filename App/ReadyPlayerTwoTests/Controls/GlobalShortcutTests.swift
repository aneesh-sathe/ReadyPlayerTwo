import Testing
@testable import ReadyPlayerTwo

@Suite(.serialized)
@MainActor
struct GlobalShortcutTests {
  @Test
  func defaultSummonUsesControlShiftSpace() {
    let shortcut = GlobalShortcut.defaultSummon

    #expect(shortcut.keyCode == 49)
    #expect(shortcut.modifiers == [.control, .shift])
  }

  @Test
  func successfulRegistrationInvokesAndUnregistersExactlyOnce() {
    let registrar = FakeGlobalShortcutRegistrar()
    let controller = GlobalShortcutController(registrar: registrar)
    var invocationCount = 0

    let state = controller.activate(.defaultSummon) {
      invocationCount += 1
    }

    #expect(state == .registered(.defaultSummon))
    #expect(registrar.requestedShortcuts == [.defaultSummon])

    registrar.invoke()
    #expect(invocationCount == 1)

    controller.deactivate()
    controller.deactivate()

    #expect(controller.state == .inactive)
    #expect(registrar.unregisterCount == 1)

    registrar.invoke()
    #expect(invocationCount == 1)
  }

  @Test
  func registrationConflictIsReportedWithoutAnActiveCallback() {
    let registrar = FakeGlobalShortcutRegistrar(outcome: .conflict)
    let controller = GlobalShortcutController(registrar: registrar)
    var invocationCount = 0

    let state = controller.activate(.defaultSummon) {
      invocationCount += 1
    }

    #expect(state == .conflict(.defaultSummon))
    #expect(registrar.requestedShortcuts == [.defaultSummon])
    #expect(registrar.unregisterCount == 0)

    registrar.invoke()
    #expect(invocationCount == 0)
  }

  @Test
  func replacingARegistrationUnregistersThePreviousShortcut() {
    let registrar = FakeGlobalShortcutRegistrar()
    let controller = GlobalShortcutController(registrar: registrar)
    let replacement = GlobalShortcut(
      keyCode: 1,
      modifiers: [.command, .shift]
    )

    _ = controller.activate(.defaultSummon) {}
    _ = controller.activate(replacement) {}

    #expect(
      registrar.requestedShortcuts == [
        .defaultSummon,
        replacement,
      ]
    )
    #expect(registrar.unregisterCount == 1)
    #expect(controller.state == .registered(replacement))
  }
}

@MainActor
private final class FakeGlobalShortcutRegistrar: GlobalShortcutRegistering {
  enum Outcome {
    case success
    case conflict
  }

  private let outcome: Outcome
  private var invocation: (@MainActor () -> Void)?
  private(set) var requestedShortcuts: [GlobalShortcut] = []
  private(set) var unregisterCount = 0

  init(outcome: Outcome = .success) {
    self.outcome = outcome
  }

  func register(
    _ shortcut: GlobalShortcut,
    onInvocation: @escaping @MainActor () -> Void
  ) throws -> any GlobalShortcutRegistration {
    requestedShortcuts.append(shortcut)

    switch outcome {
    case .success:
      invocation = onInvocation
      return FakeGlobalShortcutRegistration { [weak self] in
        guard let self else {
          return
        }
        unregisterCount += 1
        invocation = nil
      }
    case .conflict:
      throw GlobalShortcutRegistrationError.conflict
    }
  }

  func invoke() {
    invocation?()
  }
}

@MainActor
private final class FakeGlobalShortcutRegistration: GlobalShortcutRegistration {
  private let onUnregister: @MainActor () -> Void
  private var isRegistered = true

  init(onUnregister: @escaping @MainActor () -> Void) {
    self.onUnregister = onUnregister
  }

  func unregister() {
    guard isRegistered else {
      return
    }

    isRegistered = false
    onUnregister()
  }
}
