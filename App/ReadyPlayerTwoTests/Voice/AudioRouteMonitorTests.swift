import CoreAudio
import Testing

@testable import ReadyPlayerTwo

@MainActor
struct AudioRouteMonitorTests {
  @Test
  func changedDataSourceOnCurrentDevicePublishesOneRouteEvent()
    async throws
  {
    let initialRoute = AudioRouteSnapshot(
      inputDevice: AudioDeviceID(17),
      outputDevice: AudioDeviceID(23),
      inputDataSource: 41,
      outputDataSource: 43
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
      inputDataSource: 47,
      outputDataSource: 43
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
