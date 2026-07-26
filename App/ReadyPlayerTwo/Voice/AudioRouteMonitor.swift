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
private final class CoreAudioDefaultRouteHardware:
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

  private var listener: AudioObjectPropertyListenerBlock?
  private var installedAddresses: [AudioObjectPropertyAddress] = []
  private var didChange: (@MainActor @Sendable () -> Void)?

  func defaultRoute() throws -> AudioRouteSnapshot {
    AudioRouteSnapshot(
      inputDevice: try device(
        for: kAudioHardwarePropertyDefaultInputDevice
      ),
      outputDevice: try device(
        for: kAudioHardwarePropertyDefaultOutputDevice
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
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var device = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &device
    )
    guard status == noErr else {
      throw Self.failure(
        "The default audio route could not be read."
      )
    }
    return device
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
