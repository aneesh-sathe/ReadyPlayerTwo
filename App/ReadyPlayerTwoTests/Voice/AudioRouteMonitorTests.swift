import CoreAudio
import Testing

@testable import ReadyPlayerTwo

@MainActor
struct AudioRouteMonitorTests {
  @Test
  func hardwareReadsEverySelectedDataSource() throws {
    let defaultInput = AudioRouteProperty(
      objectID: AudioObjectID(kAudioObjectSystemObject),
      selector: kAudioHardwarePropertyDefaultInputDevice,
      scope: kAudioObjectPropertyScopeGlobal
    )
    let defaultOutput = AudioRouteProperty(
      objectID: AudioObjectID(kAudioObjectSystemObject),
      selector: kAudioHardwarePropertyDefaultOutputDevice,
      scope: kAudioObjectPropertyScopeGlobal
    )
    let inputDataSource = AudioRouteProperty(
      objectID: AudioObjectID(17),
      selector: kAudioDevicePropertyDataSource,
      scope: kAudioDevicePropertyScopeInput
    )
    let properties = ScriptedAudioRouteProperties(
      values: [
        defaultInput: 17,
        defaultOutput: 23,
      ],
      arrayValues: [
        inputDataSource: [41, 47]
      ]
    )
    let hardware = CoreAudioDefaultRouteHardware(properties: properties)

    #expect(
      try hardware.defaultRoute()
        == AudioRouteSnapshot(
          inputDevice: AudioDeviceID(17),
          outputDevice: AudioDeviceID(23),
          inputDataSources: [41, 47],
          outputDataSources: nil
        )
    )
  }

  @Test
  func queuedDefaultRouteCallbackCannotReinstallAfterStop() throws {
    let defaultInput = AudioRouteProperty(
      objectID: AudioObjectID(kAudioObjectSystemObject),
      selector: kAudioHardwarePropertyDefaultInputDevice,
      scope: kAudioObjectPropertyScopeGlobal
    )
    let defaultOutput = AudioRouteProperty(
      objectID: AudioObjectID(kAudioObjectSystemObject),
      selector: kAudioHardwarePropertyDefaultOutputDevice,
      scope: kAudioObjectPropertyScopeGlobal
    )
    let inputDataSource = AudioRouteProperty(
      objectID: AudioObjectID(17),
      selector: kAudioDevicePropertyDataSource,
      scope: kAudioDevicePropertyScopeInput
    )
    let outputDataSource = AudioRouteProperty(
      objectID: AudioObjectID(23),
      selector: kAudioDevicePropertyDataSource,
      scope: kAudioDevicePropertyScopeOutput
    )
    let properties = ScriptedAudioRouteProperties(
      values: [
        defaultInput: 17,
        defaultOutput: 23,
        inputDataSource: 41,
        outputDataSource: 43,
      ]
    )
    let hardware = CoreAudioDefaultRouteHardware(properties: properties)
    let recorder = AudioRouteChangeRecorder()
    try hardware.observeDefaultRoute {
      recorder.count += 1
    }
    let queuedCallback = try #require(
      properties.callback(for: defaultInput)
    )

    hardware.stopObservingDefaultRoute()
    queuedCallback()

    #expect(properties.activeObservations.isEmpty)
    #expect(recorder.count == 0)
  }

  @Test
  func listenerFailureCleansUpEveryInstalledObservation() {
    let defaultInput = AudioRouteProperty(
      objectID: AudioObjectID(kAudioObjectSystemObject),
      selector: kAudioHardwarePropertyDefaultInputDevice,
      scope: kAudioObjectPropertyScopeGlobal
    )
    let defaultOutput = AudioRouteProperty(
      objectID: AudioObjectID(kAudioObjectSystemObject),
      selector: kAudioHardwarePropertyDefaultOutputDevice,
      scope: kAudioObjectPropertyScopeGlobal
    )
    let inputDataSource = AudioRouteProperty(
      objectID: AudioObjectID(17),
      selector: kAudioDevicePropertyDataSource,
      scope: kAudioDevicePropertyScopeInput
    )
    let outputDataSource = AudioRouteProperty(
      objectID: AudioObjectID(23),
      selector: kAudioDevicePropertyDataSource,
      scope: kAudioDevicePropertyScopeOutput
    )
    let properties = ScriptedAudioRouteProperties(
      values: [
        defaultInput: 17,
        defaultOutput: 23,
        inputDataSource: 41,
        outputDataSource: 43,
      ]
    )
    properties.observeFailure = outputDataSource
    let hardware = CoreAudioDefaultRouteHardware(properties: properties)

    #expect(throws: (any Error).self) {
      try hardware.observeDefaultRoute {}
    }

    #expect(properties.activeObservations.isEmpty)
    #expect(properties.stoppedObservations.count == 3)

    hardware.stopObservingDefaultRoute()
    #expect(properties.stoppedObservations.count == 3)
  }

  @Test
  func hardwareMovesSourceObservationToNewDefaultDevice() throws {
    let defaultInput = AudioRouteProperty(
      objectID: AudioObjectID(kAudioObjectSystemObject),
      selector: kAudioHardwarePropertyDefaultInputDevice,
      scope: kAudioObjectPropertyScopeGlobal
    )
    let defaultOutput = AudioRouteProperty(
      objectID: AudioObjectID(kAudioObjectSystemObject),
      selector: kAudioHardwarePropertyDefaultOutputDevice,
      scope: kAudioObjectPropertyScopeGlobal
    )
    let oldInputDataSource = AudioRouteProperty(
      objectID: AudioObjectID(17),
      selector: kAudioDevicePropertyDataSource,
      scope: kAudioDevicePropertyScopeInput
    )
    let newInputDataSource = AudioRouteProperty(
      objectID: AudioObjectID(31),
      selector: kAudioDevicePropertyDataSource,
      scope: kAudioDevicePropertyScopeInput
    )
    let outputDataSource = AudioRouteProperty(
      objectID: AudioObjectID(23),
      selector: kAudioDevicePropertyDataSource,
      scope: kAudioDevicePropertyScopeOutput
    )
    let properties = ScriptedAudioRouteProperties(
      values: [
        defaultInput: 17,
        defaultOutput: 23,
        oldInputDataSource: 41,
        outputDataSource: 43,
      ]
    )
    let hardware = CoreAudioDefaultRouteHardware(properties: properties)
    let recorder = AudioRouteChangeRecorder()
    try hardware.observeDefaultRoute {
      recorder.count += 1
    }

    properties.values[defaultInput] = 31
    properties.values[oldInputDataSource] = nil
    properties.values[newInputDataSource] = 47
    properties.emitChange(for: defaultInput)

    #expect(recorder.count == 1)
    #expect(
      Set(properties.activeProperties)
        == Set([
          defaultInput,
          defaultOutput,
          newInputDataSource,
          outputDataSource,
        ])
    )

    hardware.stopObservingDefaultRoute()
    #expect(properties.activeObservations.isEmpty)
  }

  @Test
  func hardwareObservesSupportedDataSourcesAndCleansUp() throws {
    let defaultInput = AudioRouteProperty(
      objectID: AudioObjectID(kAudioObjectSystemObject),
      selector: kAudioHardwarePropertyDefaultInputDevice,
      scope: kAudioObjectPropertyScopeGlobal
    )
    let defaultOutput = AudioRouteProperty(
      objectID: AudioObjectID(kAudioObjectSystemObject),
      selector: kAudioHardwarePropertyDefaultOutputDevice,
      scope: kAudioObjectPropertyScopeGlobal
    )
    let inputDataSource = AudioRouteProperty(
      objectID: AudioObjectID(17),
      selector: kAudioDevicePropertyDataSource,
      scope: kAudioDevicePropertyScopeInput
    )
    let outputDataSource = AudioRouteProperty(
      objectID: AudioObjectID(23),
      selector: kAudioDevicePropertyDataSource,
      scope: kAudioDevicePropertyScopeOutput
    )
    let properties = ScriptedAudioRouteProperties(
      values: [
        defaultInput: 17,
        defaultOutput: 23,
        inputDataSource: 41,
        outputDataSource: 43,
      ]
    )
    let hardware = CoreAudioDefaultRouteHardware(properties: properties)
    let recorder = AudioRouteChangeRecorder()

    try hardware.observeDefaultRoute {
      recorder.count += 1
    }

    #expect(
      Set(properties.observedProperties)
        == Set([
          defaultInput,
          defaultOutput,
          inputDataSource,
          outputDataSource,
        ])
    )

    properties.values[inputDataSource] = 47
    properties.emitChange(for: inputDataSource)
    #expect(recorder.count == 1)

    let installed = Set(properties.activeObservations)
    hardware.stopObservingDefaultRoute()

    #expect(properties.activeObservations.isEmpty)
    #expect(Set(properties.stoppedObservations) == installed)
  }

  @Test
  func hardwareReadsSupportedSelectedDataSources() throws {
    let properties = ScriptedAudioRouteProperties(
      values: [
        AudioRouteProperty(
          objectID: AudioObjectID(kAudioObjectSystemObject),
          selector: kAudioHardwarePropertyDefaultInputDevice,
          scope: kAudioObjectPropertyScopeGlobal
        ): 17,
        AudioRouteProperty(
          objectID: AudioObjectID(kAudioObjectSystemObject),
          selector: kAudioHardwarePropertyDefaultOutputDevice,
          scope: kAudioObjectPropertyScopeGlobal
        ): 23,
        AudioRouteProperty(
          objectID: AudioObjectID(17),
          selector: kAudioDevicePropertyDataSource,
          scope: kAudioDevicePropertyScopeInput
        ): 41,
      ]
    )
    let hardware = CoreAudioDefaultRouteHardware(properties: properties)

    #expect(
      try hardware.defaultRoute()
        == AudioRouteSnapshot(
          inputDevice: AudioDeviceID(17),
          outputDevice: AudioDeviceID(23),
          inputDataSources: [41],
          outputDataSources: nil
        )
    )
  }

  @Test
  func changedDataSourceOnCurrentDevicePublishesOneRouteEvent()
    async throws
  {
    let initialRoute = AudioRouteSnapshot(
      inputDevice: AudioDeviceID(17),
      outputDevice: AudioDeviceID(23),
      inputDataSources: [41, 47],
      outputDataSources: [43]
    )
    let hardware = ScriptedAudioRouteHardware(route: initialRoute)
    let monitor = CoreAudioRouteMonitor(hardware: hardware)
    let recorder = AudioRouteEventRecorder()
    let recording = Task { @MainActor in
      for await event in monitor.events {
        recorder.events.append(event)
      }
    }

    try monitor.start()
    hardware.route = AudioRouteSnapshot(
      inputDevice: AudioDeviceID(17),
      outputDevice: AudioDeviceID(23),
      inputDataSources: [41, 53],
      outputDataSources: [43]
    )
    hardware.emitChange()
    hardware.emitChange()

    for _ in 0..<20 where recorder.events.isEmpty {
      await Task.yield()
    }
    recording.cancel()
    await Task.yield()

    #expect(recorder.events == [.changed])

    monitor.stop()
  }

  @Test
  func changedOutputSourceOnCurrentDevicePublishesRouteEvent()
    async throws
  {
    let hardware = ScriptedAudioRouteHardware(
      route: AudioRouteSnapshot(
        inputDevice: AudioDeviceID(17),
        outputDevice: AudioDeviceID(23),
        inputDataSources: [41],
        outputDataSources: [43]
      )
    )
    let monitor = CoreAudioRouteMonitor(hardware: hardware)
    var events = monitor.events.makeAsyncIterator()

    try monitor.start()
    hardware.route = AudioRouteSnapshot(
      inputDevice: AudioDeviceID(17),
      outputDevice: AudioDeviceID(23),
      inputDataSources: [41],
      outputDataSources: [53]
    )
    hardware.emitChange()

    #expect(await events.next() == .changed)

    monitor.stop()
  }

  @Test
  func changedDefaultDevicePublishesOneRouteEvent() async throws {
    let initialRoute = AudioRouteSnapshot(
      inputDevice: AudioDeviceID(17),
      outputDevice: AudioDeviceID(23)
    )
    let hardware = ScriptedAudioRouteHardware(route: initialRoute)
    let monitor = CoreAudioRouteMonitor(hardware: hardware)
    var events = monitor.events.makeAsyncIterator()

    try monitor.start()
    hardware.route = AudioRouteSnapshot(
      inputDevice: AudioDeviceID(31),
      outputDevice: AudioDeviceID(23)
    )
    hardware.emitChange()

    #expect(await events.next() == .changed)
    #expect(hardware.observeCount == 1)

    monitor.stop()
    #expect(hardware.stopCount == 1)
  }
}

@MainActor
private final class ScriptedAudioRouteProperties:
  AudioRoutePropertyAccessPort
{
  private struct Observation {
    let property: AudioRouteProperty
    let didChange: @MainActor @Sendable () -> Void
  }

  var values: [AudioRouteProperty: UInt32]
  var arrayValues: [AudioRouteProperty: [UInt32]]
  var observeFailure: AudioRouteProperty?
  private(set) var observedProperties: [AudioRouteProperty] = []
  private(set) var stoppedObservations: [AudioRoutePropertyObservation] = []

  var activeObservations: [AudioRoutePropertyObservation] {
    Array(observations.keys)
  }

  var activeProperties: [AudioRouteProperty] {
    observations.values.map(\.property)
  }

  private var observations: [AudioRoutePropertyObservation: Observation] = [:]

  init(
    values: [AudioRouteProperty: UInt32],
    arrayValues: [AudioRouteProperty: [UInt32]] = [:]
  ) {
    self.values = values
    self.arrayValues = arrayValues
  }

  func hasValue(for property: AudioRouteProperty) -> Bool {
    values[property] != nil || arrayValues[property] != nil
  }

  func value(for property: AudioRouteProperty) throws -> UInt32 {
    guard let value = values[property] else {
      throw CocoaError(.fileReadUnknown)
    }
    return value
  }

  func values(for property: AudioRouteProperty) throws -> [UInt32] {
    if let values = arrayValues[property] {
      return values
    }
    guard let value = values[property] else {
      throw CocoaError(.fileReadUnknown)
    }
    return [value]
  }

  func observe(
    _ property: AudioRouteProperty,
    didChange: @escaping @MainActor @Sendable () -> Void
  ) throws -> AudioRoutePropertyObservation {
    if property == observeFailure {
      throw CocoaError(.fileReadUnknown)
    }
    let observation = AudioRoutePropertyObservation()
    observedProperties.append(property)
    observations[observation] = Observation(
      property: property,
      didChange: didChange
    )
    return observation
  }

  func stopObserving(_ observation: AudioRoutePropertyObservation) {
    guard observations.removeValue(forKey: observation) != nil else {
      return
    }
    stoppedObservations.append(observation)
  }

  func emitChange(for property: AudioRouteProperty) {
    let callbacks = observations.values
      .filter { $0.property == property }
      .map(\.didChange)
    for callback in callbacks {
      callback()
    }
  }

  func callback(
    for property: AudioRouteProperty
  ) -> (@MainActor @Sendable () -> Void)? {
    observations.values.first {
      $0.property == property
    }?.didChange
  }
}

@MainActor
private final class AudioRouteChangeRecorder {
  var count = 0
}

@MainActor
private final class AudioRouteEventRecorder {
  var events: [AudioRouteMonitorEvent] = []
}

@MainActor
private final class ScriptedAudioRouteHardware:
  AudioRouteHardwarePort
{
  var route: AudioRouteSnapshot
  private(set) var observeCount = 0
  private(set) var stopCount = 0

  private var didChange: (@MainActor @Sendable () -> Void)?

  init(route: AudioRouteSnapshot) {
    self.route = route
  }

  func defaultRoute() throws -> AudioRouteSnapshot {
    route
  }

  func observeDefaultRoute(
    _ didChange: @escaping @MainActor @Sendable () -> Void
  ) throws {
    observeCount += 1
    self.didChange = didChange
  }

  func stopObservingDefaultRoute() {
    stopCount += 1
    didChange = nil
  }

  func emitChange() {
    didChange?()
  }
}
