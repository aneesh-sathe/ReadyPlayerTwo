import CompanionRuntime
import Testing

@testable import ReadyPlayerTwo

struct WebRTCLifecyclePolicyTests {
  @Test
  func disconnectedPeerBecomesRecoverableVoiceFailure() {
    let failure = WebRTCLifecyclePolicy.failure(
      for: .peerDisconnected
    )

    #expect(
      failure
        == CompanionFailure(
          kind: .peerConnection,
          message: "The voice connection was interrupted. Retry to reconnect."
        )
    )
  }

  @Test
  func closingSuppressesNativeConnectionCallbacks() {
    var gate = WebRTCLifecycleGate()
    gate.beginConnection()
    gate.beginClosing()

    #expect(gate.failure(for: .peerDisconnected) == nil)
  }
}
