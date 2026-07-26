import CompanionRuntime
import CoreAudio
import Foundation

enum AudioRouteMonitorEvent: Equatable, Sendable {
  case changed
}

@MainActor
protocol AudioRouteMonitorPort: AnyObject {
  var events: AsyncStream<AudioRouteMonitorEvent> { get }

  func start() throws
  func stop()
}

struct AudioRouteSnapshot: Equatable, Sendable {
  let inputDevice: AudioDeviceID
  let outputDevice: AudioDeviceID
  let inputDataSource: UInt32?
  let outputDataSource: UInt32?

  init(
    inputDevice: AudioDeviceID,
    outputDevice: AudioDeviceID,
    inputDataSource: UInt32? = nil,
    outputDataSource: UInt32? = nil
  ) {
    self.inputDevice = inputDevice
    self.outputDevice = outputDevice
    self.inputDataSource = inputDataSource
    self.outputDataSource = outputDataSource
  }

  var hasUsableDevices: Bool {
    inputDevice != kAudioObjectUnknown
      && outputDevice != kAudioObjectUnknown
  }
}

struct AudioRouteProperty: Hashable, Sendable {
  let objectID: AudioObjectID
  let selector: AudioObjectPropertySelector
  let scope: AudioObjectPropertyScope
  let element: AudioObjectPropertyElement

  init(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope,
    element: AudioObjectPropertyElement =
      kAudioObjectPropertyElementMain
  ) {
    self.objectID = objectID
    self.selector = selector
    self.scope = scope
    self.element = element
  }

  var address: AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: scope,
      mElement: element
    )
  }
}

struct AudioRoutePropertyObservation: Hashable, Sendable {
  fileprivate let id: UUID

  init() {
    id = UUID()
  }
}

@MainActor
protocol AudioRoutePropertyAccessPort: AnyObject {
  func hasValue(for property: AudioRouteProperty) -> Bool
  func value(for property: AudioRouteProperty) throws -> UInt32
  func observe(
    _ property: AudioRouteProperty,
    didChange: @escaping @MainActor @Sendable () -> Void
  ) throws -> AudioRoutePropertyObservation
  func stopObserving(_ observation: AudioRoutePropertyObservation)
}

@MainActor
protocol AudioRouteHardwarePort: AnyObject {
  func defaultRoute() throws -> AudioRouteSnapshot
  func observeDefaultRoute(
    _ didChange: @escaping @MainActor @Sendable () -> Void
  ) throws
  func stopObservingDefaultRoute()
}

@MainActor
final class CoreAudioRouteMonitor: AudioRouteMonitorPort {
  let events: AsyncStream<AudioRouteMonitorEvent>

  private let hardware: any AudioRouteHardwarePort
  private let continuation: AsyncStream<AudioRouteMonitorEvent>.Continuation

  private var route: AudioRouteSnapshot?
  private var isRunning = false

  init(
    hardware: any AudioRouteHardwarePort =
      CoreAudioDefaultRouteHardware()
  ) {
    self.hardware = hardware
    let pair = AsyncStream<AudioRouteMonitorEvent>.makeStream()
    events = pair.stream
    continuation = pair.continuation
  }

  func start() throws {
    guard !isRunning else {
      return
    }

    let initialRoute = try hardware.defaultRoute()
    guard initialRoute.hasUsableDevices else {
      throw Self.failure(
        "No default input or output audio device is available."
      )
    }

    route = initialRoute
    try hardware.observeDefaultRoute { [weak self] in
      self?.refreshRoute()
    }
    isRunning = true
    refreshRoute()
  }

  func stop() {
    guard isRunning else {
      return
    }
    hardware.stopObservingDefaultRoute()
    route = nil
    isRunning = false
  }

  private func refreshRoute() {
    guard isRunning, let route else {
      return
    }

    let newRoute: AudioRouteSnapshot
    do {
      newRoute = try hardware.defaultRoute()
    } catch {
      continuation.yield(.changed)
      return
    }

    guard newRoute != route else {
      return
    }
    self.route = newRoute
    continuation.yield(.changed)
  }

  private static func failure(_ message: String) -> CompanionFailure {
    CompanionFailure(kind: .audioRoute, message: message)
  }
}

@MainActor
final class CoreAudioDefaultRouteHardware:
  AudioRouteHardwarePort
{
  private static let addresses = [
    AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    ),
    AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    ),
  ]

  private let callbackQueue = DispatchQueue(
    label: "com.aneeshsathe.readyplayertwo.audio-route"
  )
  private let properties: any AudioRoutePropertyAccessPort

  private var listener: AudioObjectPropertyListenerBlock?
  private var installedAddresses: [AudioObjectPropertyAddress] = []
  private var didChange: (@MainActor @Sendable () -> Void)?

  init(
    properties: any AudioRoutePropertyAccessPort =
      CoreAudioRoutePropertyAccess()
  ) {
    self.properties = properties
  }

  func defaultRoute() throws -> AudioRouteSnapshot {
    let inputDevice = try device(
      for: kAudioHardwarePropertyDefaultInputDevice
    )
    let outputDevice = try device(
      for: kAudioHardwarePropertyDefaultOutputDevice
    )
    return AudioRouteSnapshot(
      inputDevice: inputDevice,
      outputDevice: outputDevice,
      inputDataSource: selectedDataSource(
        for: inputDevice,
        scope: kAudioDevicePropertyScopeInput
      ),
      outputDataSource: selectedDataSource(
        for: outputDevice,
        scope: kAudioDevicePropertyScopeOutput
      )
    )
  }

  func observeDefaultRoute(
    _ didChange: @escaping @MainActor @Sendable () -> Void
  ) throws {
    guard listener == nil else {
      return
    }

    self.didChange = didChange
    let listener: AudioObjectPropertyListenerBlock = {
      [weak self] _, _ in
      Task { @MainActor [weak self] in
        self?.didChange?()
      }
    }

    var installed: [AudioObjectPropertyAddress] = []
    do {
      for var address in Self.addresses {
        let status = AudioObjectAddPropertyListenerBlock(
          AudioObjectID(kAudioObjectSystemObject),
          &address,
          callbackQueue,
          listener
        )
        guard status == noErr else {
          throw Self.failure(
            "The default audio route could not be observed."
          )
        }
        installed.append(address)
      }
    } catch {
      remove(listener: listener, addresses: installed)
      self.didChange = nil
      throw error
    }

    self.listener = listener
    installedAddresses = installed
  }

  func stopObservingDefaultRoute() {
    guard let listener else {
      return
    }
    remove(listener: listener, addresses: installedAddresses)
    self.listener = nil
    installedAddresses = []
    didChange = nil
  }

  private func device(
    for selector: AudioObjectPropertySelector
  ) throws -> AudioDeviceID {
    let property = AudioRouteProperty(
      objectID: AudioObjectID(kAudioObjectSystemObject),
      selector: selector,
      scope: kAudioObjectPropertyScopeGlobal
    )
    do {
      return try properties.value(for: property)
    } catch {
      throw Self.failure(
        "The default audio route could not be read."
      )
    }
  }

  private func selectedDataSource(
    for device: AudioDeviceID,
    scope: AudioObjectPropertyScope
  ) -> UInt32? {
    guard device != kAudioObjectUnknown else {
      return nil
    }
    let property = AudioRouteProperty(
      objectID: AudioObjectID(device),
      selector: kAudioDevicePropertyDataSource,
      scope: scope
    )
    guard properties.hasValue(for: property) else {
      return nil
    }
    return try? properties.value(for: property)
  }

  private func remove(
    listener: @escaping AudioObjectPropertyListenerBlock,
    addresses: [AudioObjectPropertyAddress]
  ) {
    for var address in addresses {
      AudioObjectRemovePropertyListenerBlock(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        callbackQueue,
        listener
      )
    }
  }

  private static func failure(_ message: String) -> CompanionFailure {
    CompanionFailure(kind: .audioRoute, message: message)
  }
}

@MainActor
private final class CoreAudioRoutePropertyAccess:
  AudioRoutePropertyAccessPort
{
  private struct InstalledObservation {
    let property: AudioRouteProperty
    let listener: AudioObjectPropertyListenerBlock
  }

  private let callbackQueue = DispatchQueue(
    label: "com.aneeshsathe.readyplayertwo.audio-properties"
  )
  private var observations: [AudioRoutePropertyObservation: InstalledObservation] = [:]

  func hasValue(for property: AudioRouteProperty) -> Bool {
    var address = property.address
    return AudioObjectHasProperty(property.objectID, &address)
  }

  func value(for property: AudioRouteProperty) throws -> UInt32 {
    var address = property.address
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(
      property.objectID,
      &address,
      0,
      nil,
      &size,
      &value
    )
    guard status == noErr else {
      throw Self.failure()
    }
    return value
  }

  func observe(
    _ property: AudioRouteProperty,
    didChange: @escaping @MainActor @Sendable () -> Void
  ) throws -> AudioRoutePropertyObservation {
    let listener: AudioObjectPropertyListenerBlock = { _, _ in
      Task { @MainActor in
        didChange()
      }
    }
    var address = property.address
    let status = AudioObjectAddPropertyListenerBlock(
      property.objectID,
      &address,
      callbackQueue,
      listener
    )
    guard status == noErr else {
      throw Self.failure()
    }

    let observation = AudioRoutePropertyObservation()
    observations[observation] = InstalledObservation(
      property: property,
      listener: listener
    )
    return observation
  }

  func stopObserving(_ observation: AudioRoutePropertyObservation) {
    guard
      let installed = observations.removeValue(
        forKey: observation
      )
    else {
      return
    }
    var address = installed.property.address
    AudioObjectRemovePropertyListenerBlock(
      installed.property.objectID,
      &address,
      callbackQueue,
      installed.listener
    )
  }

  private static func failure() -> CompanionFailure {
    CompanionFailure(
      kind: .audioRoute,
      message: "An audio hardware property could not be accessed."
    )
  }
}
