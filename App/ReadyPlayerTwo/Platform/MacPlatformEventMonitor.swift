import AppKit
import CompanionRuntime

@MainActor
final class MacPlatformEventMonitor: NSObject {
  typealias EventHandler = @MainActor @Sendable (PlatformEvent) async -> Void

  private let workspaceNotificationCenter: NotificationCenter
  private let applicationNotificationCenter: NotificationCenter
  private let handleEvent: EventHandler

  private var isStarted = false
  private var pendingEvents: [PlatformEvent] = []
  private var deliveryTask: Task<Void, Never>?
  private var deliveryGeneration = 0

  init(
    workspaceNotificationCenter: NotificationCenter =
      NSWorkspace.shared.notificationCenter,
    applicationNotificationCenter: NotificationCenter = .default,
    handleEvent: @escaping EventHandler
  ) {
    self.workspaceNotificationCenter = workspaceNotificationCenter
    self.applicationNotificationCenter = applicationNotificationCenter
    self.handleEvent = handleEvent
  }

  func start() {
    guard !isStarted else {
      return
    }

    isStarted = true
    deliveryGeneration &+= 1

    workspaceNotificationCenter.addObserver(
      self,
      selector: #selector(workspaceWillSleep),
      name: NSWorkspace.willSleepNotification,
      object: nil
    )
    workspaceNotificationCenter.addObserver(
      self,
      selector: #selector(workspaceDidWake),
      name: NSWorkspace.didWakeNotification,
      object: nil
    )
    workspaceNotificationCenter.addObserver(
      self,
      selector: #selector(workspaceScreensDidSleep),
      name: NSWorkspace.screensDidSleepNotification,
      object: nil
    )
    workspaceNotificationCenter.addObserver(
      self,
      selector: #selector(workspaceScreensDidWake),
      name: NSWorkspace.screensDidWakeNotification,
      object: nil
    )
    workspaceNotificationCenter.addObserver(
      self,
      selector: #selector(workspaceSessionDidResignActive),
      name: NSWorkspace.sessionDidResignActiveNotification,
      object: nil
    )
    workspaceNotificationCenter.addObserver(
      self,
      selector: #selector(workspaceSessionDidBecomeActive),
      name: NSWorkspace.sessionDidBecomeActiveNotification,
      object: nil
    )
    workspaceNotificationCenter.addObserver(
      self,
      selector: #selector(workspaceActiveSpaceDidChange),
      name: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil
    )
    applicationNotificationCenter.addObserver(
      self,
      selector: #selector(applicationScreenParametersDidChange),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
  }

  func stop() {
    guard isStarted else {
      return
    }

    isStarted = false
    deliveryGeneration &+= 1
    pendingEvents.removeAll()
    deliveryTask?.cancel()
    deliveryTask = nil

    workspaceNotificationCenter.removeObserver(
      self,
      name: NSWorkspace.willSleepNotification,
      object: nil
    )
    workspaceNotificationCenter.removeObserver(
      self,
      name: NSWorkspace.didWakeNotification,
      object: nil
    )
    workspaceNotificationCenter.removeObserver(
      self,
      name: NSWorkspace.screensDidSleepNotification,
      object: nil
    )
    workspaceNotificationCenter.removeObserver(
      self,
      name: NSWorkspace.screensDidWakeNotification,
      object: nil
    )
    workspaceNotificationCenter.removeObserver(
      self,
      name: NSWorkspace.sessionDidResignActiveNotification,
      object: nil
    )
    workspaceNotificationCenter.removeObserver(
      self,
      name: NSWorkspace.sessionDidBecomeActiveNotification,
      object: nil
    )
    workspaceNotificationCenter.removeObserver(
      self,
      name: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil
    )
    applicationNotificationCenter.removeObserver(
      self,
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
  }

  @objc
  private func workspaceWillSleep(_: Notification) {
    enqueue(.sleep)
  }

  @objc
  private func workspaceDidWake(_: Notification) {
    enqueue(.wake)
  }

  @objc
  private func workspaceScreensDidSleep(_: Notification) {
    enqueue(.screenSaverStarted)
  }

  @objc
  private func workspaceScreensDidWake(_: Notification) {
    enqueue(.screenSaverEnded)
  }

  @objc
  private func workspaceSessionDidResignActive(_: Notification) {
    enqueue(.lock)
  }

  @objc
  private func workspaceSessionDidBecomeActive(_: Notification) {
    enqueue(.unlock)
  }

  @objc
  private func workspaceActiveSpaceDidChange(_: Notification) {
    // Active Space changes are public and safely trigger placement refresh.
    // AppKit exposes no public Mission Control start or end notification.
    enqueue(.displayConfigurationChanged)
  }

  @objc
  private func applicationScreenParametersDidChange(_: Notification) {
    enqueue(.displayConfigurationChanged)
  }

  private func enqueue(_ event: PlatformEvent) {
    guard isStarted else {
      return
    }

    pendingEvents.append(event)
    guard deliveryTask == nil else {
      return
    }

    let generation = deliveryGeneration
    deliveryTask = Task { @MainActor [weak self] in
      await self?.deliverPendingEvents(for: generation)
    }
  }

  private func deliverPendingEvents(for generation: Int) async {
    defer {
      if deliveryGeneration == generation {
        deliveryTask = nil
      }
    }

    while isStarted,
      deliveryGeneration == generation,
      !Task.isCancelled,
      !pendingEvents.isEmpty
    {
      let event = pendingEvents.removeFirst()
      await handleEvent(event)
    }
  }
}
