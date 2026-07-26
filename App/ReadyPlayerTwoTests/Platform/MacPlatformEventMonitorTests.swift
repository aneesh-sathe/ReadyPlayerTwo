import AppKit
import CompanionRuntime
import Testing

@testable import ReadyPlayerTwo

@Suite(.serialized)
@MainActor
struct MacPlatformEventMonitorTests {
  @Test
  func mapsWorkspaceAndApplicationNotificationsInOrder() async {
    let workspaceCenter = NotificationCenter()
    let applicationCenter = NotificationCenter()
    var receivedEvents: [PlatformEvent] = []
    let monitor = MacPlatformEventMonitor(
      workspaceNotificationCenter: workspaceCenter,
      applicationNotificationCenter: applicationCenter
    ) { event in
      receivedEvents.append(event)
    }

    monitor.start()
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    workspaceCenter.post(
      name: NSWorkspace.screensDidSleepNotification,
      object: nil
    )
    workspaceCenter.post(
      name: NSWorkspace.screensDidWakeNotification,
      object: nil
    )
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    workspaceCenter.post(
      name: NSWorkspace.sessionDidResignActiveNotification,
      object: nil
    )
    workspaceCenter.post(
      name: NSWorkspace.sessionDidBecomeActiveNotification,
      object: nil
    )
    workspaceCenter.post(
      name: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil
    )
    applicationCenter.post(
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
    await drainMainActorTasks()

    #expect(
      receivedEvents == [
        .sleep,
        .screenSaverStarted,
        .screenSaverEnded,
        .wake,
        .lock,
        .unlock,
        .displayConfigurationChanged,
        .displayConfigurationChanged,
      ]
    )
  }

  @Test
  func startAndStopAreIdempotentAndStopReleasesObservers() async {
    let workspaceCenter = NotificationCenter()
    let applicationCenter = NotificationCenter()
    var receivedEvents: [PlatformEvent] = []
    let monitor = MacPlatformEventMonitor(
      workspaceNotificationCenter: workspaceCenter,
      applicationNotificationCenter: applicationCenter
    ) { event in
      receivedEvents.append(event)
    }

    monitor.start()
    monitor.start()
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    await drainMainActorTasks()
    #expect(receivedEvents == [.sleep])

    monitor.stop()
    monitor.stop()
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    workspaceCenter.post(
      name: NSWorkspace.screensDidWakeNotification,
      object: nil
    )
    workspaceCenter.post(
      name: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil
    )
    applicationCenter.post(
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
    await drainMainActorTasks()
    #expect(receivedEvents == [.sleep])

    monitor.start()
    workspaceCenter.post(
      name: NSWorkspace.screensDidSleepNotification,
      object: nil
    )
    workspaceCenter.post(
      name: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil
    )
    await drainMainActorTasks()
    #expect(
      receivedEvents == [
        .sleep,
        .screenSaverStarted,
        .displayConfigurationChanged,
      ]
    )
  }

  private func drainMainActorTasks() async {
    for _ in 0..<20 {
      await Task.yield()
    }
  }
}
