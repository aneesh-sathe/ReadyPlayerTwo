import AppKit
import CompanionRuntime
import Testing

@testable import ReadyPlayerTwo

@Suite(.serialized)
struct StatusMenuPresentationTests {
  @Test
  @MainActor
  func statusMenuShowsReadinessBeforeASummon() throws {
    let controller = StatusMenuController()
    controller.install(
      actions: StatusMenuActions(
        summonOrEnd: {},
        roam: {},
        park: {},
        hideOrShow: {},
        selectAvatar: { _ in },
        moveToCurrentDisplay: {},
        muteOrUnmute: {},
        quit: {}
      )
    )
    defer {
      controller.uninstall()
    }

    let menu = try #require(controller.installedMenu)
    let diagnostics = try #require(
      menu.items.first(where: { $0.title == "Diagnostics" })?
        .submenu
    )
    let initialTitles = diagnostics.items.map(\.title)

    #expect(initialTitles.contains("Voice: Checking"))
    #expect(!initialTitles.contains("Voice: Starting"))

    controller.renderVoiceReadiness(.ready)

    let titles = diagnostics.items.map(\.title)

    #expect(titles.contains("Voice: Ready"))
    #expect(titles.contains("Broker: Healthy"))
    #expect(titles.contains("Microphone: Off"))
    #expect(
      titles.contains("Voice Processing: Remote via OpenAI")
    )
  }

  @Test
  @MainActor
  func statusMenuDisclosesProviderDataBoundariesWithoutLeaks() throws {
    let providerDetail = "upstream-request-id-secret-8675309"
    let failure = CompanionFailure(
      kind: .authentication,
      message: providerDetail
    )
    let controller = StatusMenuController()
    controller.install(
      actions: StatusMenuActions(
        summonOrEnd: {},
        roam: {},
        park: {},
        hideOrShow: {},
        selectAvatar: { _ in },
        moveToCurrentDisplay: {},
        muteOrUnmute: {},
        quit: {}
      )
    )
    defer {
      controller.uninstall()
    }

    controller.render(
      snapshot(
        voice: .error(failure),
        bubble: .error(failure.message),
        recoverableError: failure
      )
    )

    let menu = try #require(controller.installedMenu)
    let diagnostics = try #require(
      menu.items.first(where: { $0.title == "Diagnostics" })?
        .submenu
    )
    let informationalItems = [
      try #require(
        diagnostics.items.first(where: {
          $0.title == "Realtime Training: Not used by default"
        })
      ),
      try #require(
        diagnostics.items.first(where: {
          $0.title == "Realtime Application State: Not retained"
        })
      ),
      try #require(
        diagnostics.items.first(where: {
          $0.title == "Abuse Monitoring: 30 days by default"
        })
      ),
      try #require(
        diagnostics.items.first(where: {
          $0.title == "Zero Data Retention: Eligible, not guaranteed"
        })
      ),
    ]

    #expect(informationalItems.allSatisfy { !$0.isEnabled })
    #expect(
      diagnostics.items.allSatisfy {
        !$0.title.contains(providerDetail)
      }
    )
    #expect(
      diagnostics.items.contains {
        $0.title == "Voice Processing: Remote via OpenAI"
      }
    )
  }

  @Test
  @MainActor
  func statusMenuExposesAnchoredShortcutSettings() throws {
    let presenter = RecordingShortcutSettingsPresenter()
    let controller = StatusMenuController(
      shortcutSettingsPresenter: presenter
    )
    controller.install(
      actions: StatusMenuActions(
        summonOrEnd: {},
        roam: {},
        park: {},
        hideOrShow: {},
        selectAvatar: { _ in },
        moveToCurrentDisplay: {},
        muteOrUnmute: {},
        quit: {}
      )
    )
    defer {
      controller.uninstall()
    }

    let menu = try #require(controller.installedMenu)
    let item = try #require(
      menu.items.first(where: {
        $0.title == "Keyboard Shortcut…"
      })
    )

    let action = try #require(item.action)
    #expect(
      NSApp.sendAction(
        action,
        to: item.target,
        from: item
      )
    )

    #expect(presenter.positioningViews.count == 1)
    #expect(
      presenter.positioningViews.first is NSStatusBarButton
    )
  }

  @Test
  @MainActor
  func statusMenuExposesAnchoredVoiceSettings() throws {
    let presenter = RecordingVoiceSettingsPresenter()
    let controller = StatusMenuController(
      voiceSettingsPresenter: presenter
    )
    controller.install(
      actions: StatusMenuActions(
        summonOrEnd: {},
        roam: {},
        park: {},
        hideOrShow: {},
        selectAvatar: { _ in },
        moveToCurrentDisplay: {},
        muteOrUnmute: {},
        quit: {}
      )
    )
    defer {
      controller.uninstall()
    }

    let menu = try #require(controller.installedMenu)
    let item = try #require(
      menu.items.first(where: {
        $0.title == "Voice Settings…"
      })
    )

    let action = try #require(item.action)
    #expect(
      NSApp.sendAction(
        action,
        to: item.target,
        from: item
      )
    )

    #expect(presenter.positioningViews.count == 1)
    #expect(
      presenter.positioningViews.first is NSStatusBarButton
    )
  }

  @Test
  func idlePresentationReflectsPresenceAndAvatar() {
    let presentation = StatusMenuPresentation(
      snapshot: snapshot(
        avatar: .athena,
        presence: .hidden
      ),
      voiceReadiness: .notConfigured
    )

    #expect(presentation.conversationTitle == "Summon")
    #expect(presentation.conversationEnabled)
    #expect(!presentation.muteVisible)
    #expect(presentation.hideOrShowTitle == "Show Companion")
    #expect(presentation.selectedPresence == .hidden)
    #expect(presentation.selectedAvatar == .athena)
    #expect(presentation.voiceDescription == "Voice: Not Configured")
    #expect(presentation.brokerDescription == "Broker: Healthy")
    #expect(presentation.microphoneDescription == "Microphone: Off")
    #expect(
      presentation.processingDescription
        == "Voice Processing: Remote via OpenAI"
    )
  }

  @Test
  func recoverableErrorOffersRetryWithoutLeakingItsMessage() {
    let failure = CompanionFailure(
      kind: .authentication,
      message: "Sensitive upstream detail must stay out of diagnostics."
    )
    let presentation = StatusMenuPresentation(
      snapshot: snapshot(
        voice: .error(failure),
        bubble: .error(failure.message),
        recoverableError: failure
      )
    )

    #expect(presentation.conversationTitle == "Retry Voice")
    #expect(presentation.conversationEnabled)
    #expect(!presentation.muteVisible)
    #expect(presentation.voiceDescription == "Voice: Error (authentication)")
    #expect(!presentation.voiceDescription.contains("Sensitive"))
    #expect(presentation.microphoneDescription == "Microphone: Off")
  }

  @Test
  func activeAndEndingPresentationsExposeTruthfulControls() {
    let muted = StatusMenuPresentation(
      snapshot: snapshot(voice: .muted, bubble: .muted)
    )
    #expect(muted.conversationTitle == "End Conversation")
    #expect(muted.conversationEnabled)
    #expect(muted.muteVisible)
    #expect(muted.muteTitle == "Unmute Microphone")
    #expect(muted.microphoneDescription == "Microphone: Muted")

    let ending = StatusMenuPresentation(
      snapshot: snapshot(voice: .ending, bubble: .ending)
    )
    #expect(ending.conversationTitle == "Ending Conversation")
    #expect(!ending.conversationEnabled)
    #expect(!ending.muteVisible)
    #expect(ending.microphoneDescription == "Microphone: Closing")
  }

  private func snapshot(
    avatar: CompanionAvatar = .orion,
    presence: PresenceState = .roaming,
    voice: VoiceSessionState = .idle,
    bubble: BubbleState = .hidden,
    recoverableError: CompanionFailure? = nil
  ) -> CompanionSnapshot {
    CompanionSnapshot(
      avatar: avatar,
      basePresence: presence,
      isVisible: presence != .hidden || voice != .idle,
      placement: CompanionPlacement(
        displayID: "main",
        position: StagePoint(x: 720, y: 450)
      ),
      voice: voice,
      bubble: bubble,
      waveformEnergy: 0,
      recoverableError: recoverableError
    )
  }
}

@MainActor
private final class RecordingShortcutSettingsPresenter:
  ShortcutSettingsPresenting
{
  private(set) var positioningViews: [NSView] = []

  func show(relativeTo positioningView: NSView) {
    positioningViews.append(positioningView)
  }
}

@MainActor
private final class RecordingVoiceSettingsPresenter:
  VoiceSettingsPresenting
{
  private(set) var positioningViews: [NSView] = []

  func show(relativeTo positioningView: NSView) {
    positioningViews.append(positioningView)
  }
}
