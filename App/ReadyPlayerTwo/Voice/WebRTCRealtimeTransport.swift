import CompanionRuntime
import Foundation
@preconcurrency import WebRTC

@MainActor
final class WebRTCRealtimeTransport: RealtimeTransportPort {
  let events: AsyncStream<RealtimeTransportEvent>

  private static let didInitializeSSL = RTCInitializeSSL()

  private let callClient: any RealtimeCallClient
  private let continuation: AsyncStream<RealtimeTransportEvent>.Continuation

  private var factory: RTCPeerConnectionFactory?
  private var peerConnection: RTCPeerConnection?
  private var audioSource: RTCAudioSource?
  private var audioTrack: RTCAudioTrack?
  private var dataChannel: RTCDataChannel?
  private var delegateBridge: WebRTCDelegateBridge?
  private var statisticsTask: Task<Void, Never>?
  private var isClosing = false
  private var hasReportedConnectionFailure = false

  init(callClient: any RealtimeCallClient) {
    self.callClient = callClient
    let pair = AsyncStream<RealtimeTransportEvent>.makeStream()
    events = pair.stream
    continuation = pair.continuation
  }

  convenience init() throws {
    try self.init(callClient: OpenAIRealtimeCallClient())
  }

  func connect(ephemeralKey: String) async throws {
    guard Self.didInitializeSSL else {
      throw Self.peerFailure("Secure voice transport could not initialize.")
    }
    guard peerConnection == nil else {
      throw Self.peerFailure("A voice connection is already active.")
    }

    isClosing = false
    hasReportedConnectionFailure = false
    let bridge = makeDelegateBridge()
    let factory = RTCPeerConnectionFactory()
    let audioConstraints = RTCMediaConstraints(
      mandatoryConstraints: nil,
      optionalConstraints: [
        "googAutoGainControl": "true",
        "googEchoCancellation": "true",
        "googNoiseSuppression": "true",
      ]
    )
    let source = factory.audioSource(with: audioConstraints)
    let track = factory.audioTrack(
      with: source,
      trackId: "readyplayertwo-microphone"
    )

    let configuration = RTCConfiguration()
    configuration.sdpSemantics = .unifiedPlan
    let peerConstraints = RTCMediaConstraints(
      mandatoryConstraints: nil,
      optionalConstraints: nil
    )
    guard
      let peer = factory.peerConnection(
        with: configuration,
        constraints: peerConstraints,
        delegate: bridge
      ),
      peer.add(track, streamIds: ["readyplayertwo-audio"]) != nil
    else {
      throw Self.peerFailure("The microphone track could not be attached.")
    }

    let channelConfiguration = RTCDataChannelConfiguration()
    channelConfiguration.isOrdered = true
    guard
      let channel = peer.dataChannel(
        forLabel: "oai-events",
        configuration: channelConfiguration
      )
    else {
      peer.close()
      throw Self.peerFailure("The realtime event channel could not open.")
    }
    channel.delegate = bridge

    self.factory = factory
    peerConnection = peer
    audioSource = source
    audioTrack = track
    dataChannel = channel
    delegateBridge = bridge

    let offerConstraints = RTCMediaConstraints(
      mandatoryConstraints: [
        kRTCMediaConstraintsOfferToReceiveAudio:
          kRTCMediaConstraintsValueTrue,
        kRTCMediaConstraintsOfferToReceiveVideo:
          kRTCMediaConstraintsValueFalse,
      ],
      optionalConstraints: nil
    )
    let offer = try await createOffer(
      peer: peer,
      constraints: offerConstraints
    )
    try await setLocalDescription(offer, peer: peer)

    let answerSDP = try await callClient.exchangeOffer(
      offer.sdp,
      ephemeralKey: ephemeralKey
    )
    let answer = RTCSessionDescription(type: .answer, sdp: answerSDP)
    try await setRemoteDescription(answer, peer: peer)
    try await waitForEventChannelToOpen()
    startStatistics()
  }

  func send(_ event: Data) throws {
    guard
      let dataChannel,
      dataChannel.readyState == .open
    else {
      throw Self.peerFailure("The realtime event channel is not open.")
    }
    let buffer = RTCDataBuffer(data: event, isBinary: false)
    guard dataChannel.sendData(buffer) else {
      throw Self.peerFailure("A realtime event could not be sent.")
    }
  }

  func setMuted(_ isMuted: Bool) {
    audioTrack?.isEnabled = !isMuted
  }

  func close() {
    guard
      peerConnection != nil
        || dataChannel != nil
        || audioTrack != nil
    else {
      return
    }

    isClosing = true
    statisticsTask?.cancel()
    statisticsTask = nil
    audioTrack?.isEnabled = false
    dataChannel?.delegate = nil
    dataChannel?.close()
    peerConnection?.delegate = nil
    peerConnection?.close()
    dataChannel = nil
    audioTrack = nil
    audioSource = nil
    peerConnection = nil
    factory = nil
    delegateBridge = nil
  }

  private func makeDelegateBridge() -> WebRTCDelegateBridge {
    WebRTCDelegateBridge(
      onMessage: { [weak self] data in
        Task { @MainActor [weak self] in
          self?.continuation.yield(.serverMessage(data))
        }
      },
      onConnectionFailure: { [weak self] signal in
        Task { @MainActor [weak self] in
          self?.reportConnectionFailure(signal)
        }
      }
    )
  }

  private func waitForEventChannelToOpen() async throws {
    for _ in 0..<150 {
      try Task.checkCancellation()
      guard let dataChannel else {
        throw Self.peerFailure("The realtime event channel closed.")
      }

      switch dataChannel.readyState {
      case .open:
        return
      case .closing, .closed:
        throw Self.peerFailure("The realtime event channel closed.")
      case .connecting:
        try await Task.sleep(for: .milliseconds(100))
      @unknown default:
        throw Self.peerFailure("The realtime event channel is unavailable.")
      }
    }

    throw Self.peerFailure("The realtime event channel timed out.")
  }

  private func createOffer(
    peer: RTCPeerConnection,
    constraints: RTCMediaConstraints
  ) async throws -> RTCSessionDescription {
    try await withCheckedThrowingContinuation { continuation in
      peer.offer(for: constraints) { description, error in
        if let description {
          continuation.resume(returning: description)
        } else {
          continuation.resume(
            throwing: error
              ?? Self.peerFailure("The voice offer could not be created.")
          )
        }
      }
    }
  }

  private func setLocalDescription(
    _ description: RTCSessionDescription,
    peer: RTCPeerConnection
  ) async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      peer.setLocalDescription(description) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }

  private func setRemoteDescription(
    _ description: RTCSessionDescription,
    peer: RTCPeerConnection
  ) async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      peer.setRemoteDescription(description) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }

  private func startStatistics() {
    statisticsTask?.cancel()
    statisticsTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        guard let self else {
          return
        }
        let snapshot = await energySnapshot()
        if let input = snapshot.input {
          continuation.yield(.inputEnergy(input))
        }
        if let output = snapshot.output {
          continuation.yield(.outputEnergy(output))
        }
        do {
          try await Task.sleep(for: .milliseconds(100))
        } catch {
          return
        }
      }
    }
  }

  private func energySnapshot() async -> EnergySnapshot {
    guard let peerConnection else {
      return EnergySnapshot(input: nil, output: nil)
    }

    return await withCheckedContinuation { continuation in
      peerConnection.statistics { report in
        var input: Double?
        var output: Double?

        for statistic in report.statistics.values {
          let kind =
            statistic.values["kind"] as? String
            ?? statistic.values["mediaType"] as? String
          guard kind == "audio" else {
            continue
          }
          guard
            let level = statistic.values["audioLevel"] as? NSNumber
          else {
            continue
          }

          if statistic.type == "media-source" {
            input = max(input ?? 0, level.doubleValue)
          } else if statistic.type == "inbound-rtp" {
            output = max(output ?? 0, level.doubleValue)
          }
        }

        continuation.resume(
          returning: EnergySnapshot(input: input, output: output)
        )
      }
    }
  }

  private func reportConnectionFailure(
    _ signal: WebRTCLifecycleSignal
  ) {
    guard
      !isClosing,
      peerConnection != nil,
      !hasReportedConnectionFailure
    else {
      return
    }
    hasReportedConnectionFailure = true
    continuation.yield(
      .failed(WebRTCLifecyclePolicy.failure(for: signal))
    )
  }

  nonisolated private static func peerFailure(
    _ message: String
  ) -> CompanionFailure {
    CompanionFailure(kind: .peerConnection, message: message)
  }
}

enum WebRTCLifecycleSignal: Equatable, Sendable {
  case dataChannelClosed
  case iceDisconnected
  case iceFailed
  case peerDisconnected
  case peerFailed
}

enum WebRTCLifecyclePolicy {
  static func failure(
    for signal: WebRTCLifecycleSignal
  ) -> CompanionFailure {
    switch signal {
    case .dataChannelClosed:
      CompanionFailure(
        kind: .peerConnection,
        message: "The realtime event channel closed."
      )
    case .iceDisconnected, .peerDisconnected:
      CompanionFailure(
        kind: .peerConnection,
        message: "The voice connection was interrupted. Retry to reconnect."
      )
    case .iceFailed, .peerFailed:
      CompanionFailure(
        kind: .peerConnection,
        message: "The voice connection was lost."
      )
    }
  }
}

private struct EnergySnapshot: Sendable {
  let input: Double?
  let output: Double?
}

private final class WebRTCDelegateBridge:
  NSObject,
  RTCPeerConnectionDelegate,
  RTCDataChannelDelegate,
  @unchecked Sendable
{
  private let onMessage: @Sendable (Data) -> Void
  private let onConnectionFailure: @Sendable (WebRTCLifecycleSignal) -> Void

  init(
    onMessage: @escaping @Sendable (Data) -> Void,
    onConnectionFailure:
      @escaping @Sendable (
        WebRTCLifecycleSignal
      ) -> Void
  ) {
    self.onMessage = onMessage
    self.onConnectionFailure = onConnectionFailure
  }

  func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
    if dataChannel.readyState == .closed {
      onConnectionFailure(.dataChannelClosed)
    }
  }

  func dataChannel(
    _ dataChannel: RTCDataChannel,
    didReceiveMessageWith buffer: RTCDataBuffer
  ) {
    onMessage(buffer.data)
  }

  func peerConnection(
    _ peerConnection: RTCPeerConnection,
    didChange stateChanged: RTCSignalingState
  ) {}

  func peerConnection(
    _ peerConnection: RTCPeerConnection,
    didAdd stream: RTCMediaStream
  ) {}

  func peerConnection(
    _ peerConnection: RTCPeerConnection,
    didRemove stream: RTCMediaStream
  ) {}

  func peerConnectionShouldNegotiate(
    _ peerConnection: RTCPeerConnection
  ) {}

  func peerConnection(
    _ peerConnection: RTCPeerConnection,
    didChange newState: RTCIceConnectionState
  ) {
    switch newState {
    case .disconnected:
      onConnectionFailure(.iceDisconnected)
    case .failed:
      onConnectionFailure(.iceFailed)
    default:
      break
    }
  }

  func peerConnection(
    _ peerConnection: RTCPeerConnection,
    didChange newState: RTCIceGatheringState
  ) {}

  func peerConnection(
    _ peerConnection: RTCPeerConnection,
    didGenerate candidate: RTCIceCandidate
  ) {}

  func peerConnection(
    _ peerConnection: RTCPeerConnection,
    didRemove candidates: [RTCIceCandidate]
  ) {}

  func peerConnection(
    _ peerConnection: RTCPeerConnection,
    didOpen dataChannel: RTCDataChannel
  ) {
    dataChannel.delegate = self
  }

  func peerConnection(
    _ peerConnection: RTCPeerConnection,
    didChange newState: RTCPeerConnectionState
  ) {
    switch newState {
    case .disconnected:
      onConnectionFailure(.peerDisconnected)
    case .failed:
      onConnectionFailure(.peerFailed)
    default:
      break
    }
  }
}
