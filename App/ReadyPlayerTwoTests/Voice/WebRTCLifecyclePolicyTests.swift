import CompanionRuntime
import Testing

@testable import ReadyPlayerTwo

struct WebRTCLifecyclePolicyTests {
  @Test(
    arguments: [
      WebRTCLifecycleSignal.peerDisconnected,
      WebRTCLifecycleSignal.iceDisconnected,
    ]
  )
  func disconnectedTransportBecomesRecoverableVoiceFailure(
    signal: WebRTCLifecycleSignal
  ) {
    let failure = WebRTCLifecyclePolicy.failure(
      for: signal
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
