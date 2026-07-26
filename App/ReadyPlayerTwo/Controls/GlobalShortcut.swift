import Carbon
import Foundation

struct ShortcutModifiers: OptionSet, Codable, Equatable, Sendable {
  let rawValue: UInt32

  init(rawValue: UInt32) {
    self.rawValue = rawValue
  }

  static let command = Self(rawValue: UInt32(cmdKey))
  static let control = Self(rawValue: UInt32(controlKey))
  static let option = Self(rawValue: UInt32(optionKey))
  static let shift = Self(rawValue: UInt32(shiftKey))

  static let allowed: Self = [.command, .control, .option, .shift]

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    rawValue = try container.decode(UInt32.self)
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct GlobalShortcut: Codable, Equatable, Sendable {
  let keyCode: UInt32
  let modifiers: ShortcutModifiers

  static let defaultSummon = Self(
    keyCode: UInt32(kVK_Space),
    modifiers: [.control, .shift]
  )

  var isValid: Bool {
    keyCode <= 127
      && !modifiers.isEmpty
      && modifiers.subtracting(.allowed).isEmpty
  }
}

enum GlobalShortcutRegistrationError: Error, Equatable {
  case conflict
  case invalidShortcut
  case systemFailure(Int32)
}

enum GlobalShortcutState: Equatable {
  case inactive
  case registered(GlobalShortcut)
  case conflict(GlobalShortcut)
  case failed(GlobalShortcut, status: Int32)
}

@MainActor
protocol GlobalShortcutRegistration: AnyObject {
  func unregister()
}

@MainActor
protocol GlobalShortcutRegistering: AnyObject {
  func register(
    _ shortcut: GlobalShortcut,
    onInvocation: @escaping @MainActor () -> Void
  ) throws -> any GlobalShortcutRegistration
}

@MainActor
final class GlobalShortcutController {
  private let registrar: any GlobalShortcutRegistering
  private var registration: (any GlobalShortcutRegistration)?

  private(set) var state = GlobalShortcutState.inactive

  init(registrar: any GlobalShortcutRegistering) {
    self.registrar = registrar
  }

  @discardableResult
  func activate(
    _ shortcut: GlobalShortcut,
    onInvocation: @escaping @MainActor () -> Void
  ) -> GlobalShortcutState {
    deactivate()

    do {
      registration = try registrar.register(
        shortcut,
        onInvocation: onInvocation
      )
      state = .registered(shortcut)
    } catch GlobalShortcutRegistrationError.conflict {
      state = .conflict(shortcut)
    } catch GlobalShortcutRegistrationError.invalidShortcut {
      state = .failed(shortcut, status: Int32(paramErr))
    } catch GlobalShortcutRegistrationError.systemFailure(let status) {
      state = .failed(shortcut, status: status)
    } catch {
      state = .failed(shortcut, status: Int32(paramErr))
    }

    return state
  }

  func deactivate() {
    registration?.unregister()
    registration = nil
    state = .inactive
  }
}

@MainActor
final class CarbonGlobalShortcutRegistrar: GlobalShortcutRegistering {
  private struct Entry {
    let hotKey: EventHotKeyRef
    let invocation: @MainActor () -> Void
  }

  private static let signature: OSType = 0x5250_5432

  private var entries: [UInt32: Entry] = [:]
  private var eventHandler: EventHandlerRef?
  private var nextIdentifier: UInt32 = 1

  func register(
    _ shortcut: GlobalShortcut,
    onInvocation: @escaping @MainActor () -> Void
  ) throws -> any GlobalShortcutRegistration {
    guard shortcut.isValid else {
      throw GlobalShortcutRegistrationError.invalidShortcut
    }

    try installEventHandlerIfNeeded()

    let identifier = nextIdentifier
    nextIdentifier &+= 1

    let hotKeyID = EventHotKeyID(
      signature: Self.signature,
      id: identifier
    )
    var hotKey: EventHotKeyRef?
    let status = RegisterEventHotKey(
      shortcut.keyCode,
      shortcut.modifiers.rawValue,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKey
    )

    guard status == noErr, let hotKey else {
      removeEventHandlerIfUnused()
      if status == eventHotKeyExistsErr {
        throw GlobalShortcutRegistrationError.conflict
      }
      throw GlobalShortcutRegistrationError.systemFailure(Int32(status))
    }

    entries[identifier] = Entry(
      hotKey: hotKey,
      invocation: onInvocation
    )
    return CarbonGlobalShortcutRegistration(
      identifier: identifier,
      registrar: self
    )
  }

  fileprivate func unregister(identifier: UInt32) {
    guard let entry = entries.removeValue(forKey: identifier) else {
      return
    }

    UnregisterEventHotKey(entry.hotKey)
    removeEventHandlerIfUnused()
  }

  fileprivate func receive(
    signature: OSType,
    identifier: UInt32
  ) -> OSStatus {
    guard signature == Self.signature else {
      return OSStatus(eventNotHandledErr)
    }
    guard let entry = entries[identifier] else {
      return OSStatus(eventNotHandledErr)
    }

    entry.invocation()
    return noErr
  }

  private func installEventHandlerIfNeeded() throws {
    guard eventHandler == nil else {
      return
    }

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    var installedHandler: EventHandlerRef?
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      carbonGlobalShortcutHandler,
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &installedHandler
    )

    guard status == noErr, let installedHandler else {
      throw GlobalShortcutRegistrationError.systemFailure(Int32(status))
    }

    eventHandler = installedHandler
  }

  private func removeEventHandlerIfUnused() {
    guard entries.isEmpty, let eventHandler else {
      return
    }

    RemoveEventHandler(eventHandler)
    self.eventHandler = nil
  }
}

@MainActor
private final class CarbonGlobalShortcutRegistration:
  GlobalShortcutRegistration
{
  private let identifier: UInt32
  private weak var registrar: CarbonGlobalShortcutRegistrar?
  private var isRegistered = true

  init(
    identifier: UInt32,
    registrar: CarbonGlobalShortcutRegistrar
  ) {
    self.identifier = identifier
    self.registrar = registrar
  }

  func unregister() {
    guard isRegistered else {
      return
    }

    isRegistered = false
    registrar?.unregister(identifier: identifier)
  }
}

private func carbonGlobalShortcutHandler(
  _: EventHandlerCallRef?,
  event: EventRef?,
  context: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let event, let context else {
    return OSStatus(eventNotHandledErr)
  }

  var hotKeyID = EventHotKeyID()
  let status = GetEventParameter(
    event,
    EventParamName(kEventParamDirectObject),
    EventParamType(typeEventHotKeyID),
    nil,
    MemoryLayout<EventHotKeyID>.size,
    nil,
    &hotKeyID
  )
  guard status == noErr else {
    return status
  }
  let signature = hotKeyID.signature
  let identifier = hotKeyID.id

  let registrar = Unmanaged<CarbonGlobalShortcutRegistrar>
    .fromOpaque(context)
    .takeUnretainedValue()
  return MainActor.assumeIsolated {
    registrar.receive(
      signature: signature,
      identifier: identifier
    )
  }
}
