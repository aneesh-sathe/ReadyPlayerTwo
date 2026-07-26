import CompanionRuntime
import Testing
@testable import ReadyPlayerTwo

@Suite(.serialized)
struct StatusMenuPresentationTests {
  @Test
  func idlePresentationReflectsPresenceAndAvatar() {
    let presentation = StatusMenuPresentation(
      snapshot: snapshot(
        avatar: .athena,
        presence: .hidden
      )
    )

    #expect(presentation.conversationTitle == "Summon")
    #expect(presentation.conversationEnabled)
    #expect(!presentation.muteVisible)
    #expect(presentation.hideOrShowTitle == "Show Companion")
    #expect(presentation.selectedPresence == .hidden)
    #expect(presentation.selectedAvatar == .athena)
    #expect(presentation.voiceDescription == "Voice: Idle")
    #expect(presentation.microphoneDescription == "Microphone: Off")
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
