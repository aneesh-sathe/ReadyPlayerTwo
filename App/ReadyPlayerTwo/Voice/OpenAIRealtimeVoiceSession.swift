@preconcurrency import AVFoundation
import CompanionRuntime
import Foundation

@MainActor
protocol MicrophonePermissionPort {
  func requestAccess() async -> Bool
}

@MainActor
struct SystemMicrophonePermission: MicrophonePermissionPort {
  func requestAccess() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      return true
    case .notDetermined:
      return await AVCaptureDevice.requestAccess(for: .audio)
    case .denied, .restricted:
      return false
    @unknown default:
      return false
    }
  }
}

enum RealtimeTransportEvent: Equatable, Sendable {
  case serverMessage(Data)
  case inputEnergy(Double)
  case outputEnergy(Double)
  case failed(CompanionFailure)
}

@MainActor
protocol RealtimeTransportPort: AnyObject {
  var events: AsyncStream<RealtimeTransportEvent> { get }

  func connect(ephemeralKey: String) async throws
  func send(_ event: Data) throws
  func setMuted(_ isMuted: Bool)
  func close()
}

@MainActor
final class OpenAIRealtimeVoiceSession: VoiceSessionPort {
  let events: AsyncStream<VoiceSessionEvent>

  private enum Lifecycle {
    case idle
    case starting
    case active
    case failed
  }

  private enum ConversationPhase {
    case listening
    case thinking
    case speaking
    case muted
  }

  private let microphonePermission: any MicrophonePermissionPort
  private let broker: any BrokerClientPort
  private let transport: any RealtimeTransportPort
  private let continuation: AsyncStream<VoiceSessionEvent>.Continuation

  private var lifecycle = Lifecycle.idle
  private var phase = ConversationPhase.listening
  private var phaseBeforeMute = ConversationPhase.listening
  private var transportEventTask: Task<Void, Never>?

  init(
    microphonePermission: any MicrophonePermissionPort =
      SystemMicrophonePermission(),
    broker: any BrokerClientPort,
    transport: any RealtimeTransportPort
  ) {
    self.microphonePermission = microphonePermission
    self.broker = broker
    self.transport = transport

    let pair = AsyncStream<VoiceSessionEvent>.makeStream()
    events = pair.stream
    continuation = pair.continuation
  }

  func start() async throws {
    guard lifecycle == .idle || lifecycle == .failed else {
      return
    }
    lifecycle = .starting
    phase = .listening

    guard await microphonePermission.requestAccess() else {
      lifecycle = .idle
      throw CompanionFailure(
        kind: .microphoneDenied,
        message: "Microphone access is required to start a conversation."
      )
    }

    let secret: EphemeralClientSecret
    do {
      secret = try await broker.fetchClientSecret()
    } catch {
      lifecycle = .idle
      throw Self.failure(for: error, boundary: .broker)
    }

    observeTransport()
    var ephemeralKey = secret.value
    defer {
      ephemeralKey.removeAll(keepingCapacity: false)
    }

    do {
      try await transport.connect(ephemeralKey: ephemeralKey)
      guard lifecycle == .starting else {
        throw CompanionFailure(
          kind: .peerConnection,
          message: "The voice connection closed while starting."
        )
      }
      try transport.send(Self.sessionUpdate())
      lifecycle = .active
    } catch {
      transportEventTask?.cancel()
      transportEventTask = nil
      transport.close()
      lifecycle = .idle
      throw Self.failure(for: error, boundary: .transport)
    }
  }

  func stop() async {
    guard lifecycle == .starting || lifecycle == .active else {
      return
    }

    transportEventTask?.cancel()
    transportEventTask = nil
    transport.close()
    lifecycle = .idle
    phase = .listening
    continuation.yield(.ended)
  }

  func setMuted(_ isMuted: Bool) async {
    guard lifecycle == .active else {
      return
    }

    transport.setMuted(isMuted)
    if isMuted {
      if phase != .muted {
        phaseBeforeMute = phase
      }
      phase = .muted
      continuation.yield(.muted)
    } else {
      phase = phaseBeforeMute
      continuation.yield(event(for: phase))
    }
  }

  private func observeTransport() {
    transportEventTask?.cancel()
    let transportEvents = transport.events
    transportEventTask = Task { @MainActor [weak self] in
      for await event in transportEvents {
        guard let self, !Task.isCancelled else {
          return
        }
        receive(event)
      }
    }
  }

  private func receive(_ event: RealtimeTransportEvent) {
    guard lifecycle == .starting || lifecycle == .active else {
      return
    }

    switch event {
    case .serverMessage(let data):
      receiveServerMessage(data)
    case .inputEnergy(let energy):
      guard phase == .listening else {
        return
      }
      continuation.yield(.audioEnergy(Self.normalized(energy)))
    case .outputEnergy(let energy):
      guard phase == .speaking else {
        return
      }
      continuation.yield(.audioEnergy(Self.normalized(energy)))
    case .failed(let failure):
      fail(failure)
    }
  }

  private func receiveServerMessage(_ data: Data) {
    guard
      let event = try? JSONDecoder().decode(ServerEvent.self, from: data)
    else {
      return
    }

    switch event.type {
    case "session.updated":
      transition(to: .listening)
    case "input_audio_buffer.speech_started":
      if phase == .speaking {
        do {
          try transport.send(Self.event(named: "response.cancel"))
          try transport.send(
            Self.event(named: "output_audio_buffer.clear")
          )
        } catch {
          fail(Self.failure(for: error, boundary: .transport))
          return
        }
      }
      transition(to: .listening)
    case "input_audio_buffer.speech_stopped", "response.created":
      transition(to: .thinking)
    case "output_audio_buffer.started":
      transition(to: .speaking)
    case "output_audio_buffer.stopped", "response.cancelled":
      transition(to: .listening)
    case "response.done":
      if event.response?.status == "cancelled"
        || event.response?.status == "failed"
      {
        transition(to: .listening)
      }
    case "error":
      fail(
        CompanionFailure(
          kind: Self.kind(forServerErrorCode: event.error?.code),
          message: event.error?.message
            ?? "The realtime service reported an error."
        )
      )
    default:
      break
    }
  }

  private func transition(to newPhase: ConversationPhase) {
    guard phase != .muted else {
      phaseBeforeMute = newPhase
      return
    }
    phase = newPhase
    continuation.yield(event(for: newPhase))
  }

  private func event(
    for phase: ConversationPhase
  ) -> VoiceSessionEvent {
    switch phase {
    case .listening:
      .listening
    case .thinking:
      .thinking
    case .speaking:
      .speaking
    case .muted:
      .muted
    }
  }

  private func fail(_ failure: CompanionFailure) {
    guard lifecycle == .starting || lifecycle == .active else {
      return
    }
    lifecycle = .failed
    transportEventTask?.cancel()
    transportEventTask = nil
    transport.close()
    continuation.yield(.failed(failure))
  }

  private static func sessionUpdate() throws -> Data {
    let object: [String: Any] = [
      "type": "session.update",
      "session": [
        "type": "realtime",
        "model": "gpt-realtime-2.1",
        "instructions":
          """
        You are a warm, concise desktop companion. The person summoned you, \
        so follow their lead and keep the exchange natural. You have no \
        screen context in this version. Never claim to see their screen or \
        infer what app or document they are using.
        """,
        "output_modalities": ["audio"],
        "tools": [],
        "audio": [
          "input": [
            "turn_detection": [
              "type": "semantic_vad",
              "eagerness": "low",
              "create_response": true,
              "interrupt_response": true,
            ]
          ],
          "output": [
            "voice": "marin"
          ],
        ],
      ],
    ]
    return try JSONSerialization.data(withJSONObject: object)
  }

  private static func event(named type: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["type": type])
  }

  private static func normalized(_ energy: Double) -> Double {
    guard energy.isFinite else {
      return 0
    }
    return min(max(energy, 0), 1)
  }

  private enum FailureBoundary {
    case broker
    case transport
  }

  private static func failure(
    for error: any Error,
    boundary: FailureBoundary
  ) -> CompanionFailure {
    if let failure = error as? CompanionFailure {
      return failure
    }
    if let error = error as? BrokerClientError {
      switch error {
      case .missingConfiguration, .invalidOrigin:
        return CompanionFailure(
          kind: .voiceNotConfigured,
          message: "The local voice broker is not configured."
        )
      case .unsuccessfulResponse(let status)
      where status == 401 || status == 403:
        return CompanionFailure(
          kind: .authentication,
          message: "The local voice broker rejected this app."
        )
      case .unsuccessfulResponse(let status) where status == 429:
        return CompanionFailure(
          kind: .rateLimited,
          message: "Voice is temporarily rate limited."
        )
      case .invalidResponse, .unsuccessfulResponse, .malformedSecret:
        return CompanionFailure(
          kind: .brokerUnavailable,
          message: "The local voice broker is unavailable."
        )
      }
    }
    if let error = error as? RealtimeCallClientError {
      switch error {
      case .unsuccessfulResponse(let status)
      where status == 401 || status == 403:
        return CompanionFailure(
          kind: .authentication,
          message: "The realtime service rejected the session."
        )
      case .unsuccessfulResponse(let status) where status == 429:
        return CompanionFailure(
          kind: .rateLimited,
          message: "Voice is temporarily rate limited."
        )
      case .invalidEndpoint, .unsuccessfulResponse, .malformedAnswer:
        return CompanionFailure(
          kind: .peerConnection,
          message: "The voice connection could not be negotiated."
        )
      }
    }
    if error is URLError {
      return CompanionFailure(
        kind: .network,
        message: "The network connection to voice failed."
      )
    }

    return CompanionFailure(
      kind: boundary == .broker ? .brokerUnavailable : .peerConnection,
      message: boundary == .broker
        ? "The local voice broker is unavailable."
        : "The voice connection could not start."
    )
  }

  private static func kind(
    forServerErrorCode code: String?
  ) -> CompanionFailure.Kind {
    switch code {
    case "invalid_api_key", "authentication_error":
      .authentication
    case "rate_limit_exceeded":
      .rateLimited
    default:
      .network
    }
  }
}

private struct ServerEvent: Decodable {
  let type: String
  let error: ServerError?
  let response: ServerResponse?
}

private struct ServerError: Decodable {
  let code: String?
  let message: String?
}

private struct ServerResponse: Decodable {
  let status: String?
}
