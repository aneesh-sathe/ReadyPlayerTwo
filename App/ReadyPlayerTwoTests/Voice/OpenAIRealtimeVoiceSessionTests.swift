import CompanionRuntime
import Foundation
import Testing

@testable import ReadyPlayerTwo

@MainActor
struct OpenAIRealtimeVoiceSessionTests {
  @Test
  func configuresAudioForPersonFirstLowSemanticVAD() async throws {
    let permission = StubMicrophonePermission(isGranted: true)
    let broker = StubBrokerClient()
    let transport = ScriptedRealtimeTransport()
    let session = OpenAIRealtimeVoiceSession(
      microphonePermission: permission,
      broker: broker,
      transport: transport
    )
    var events = session.events.makeAsyncIterator()

    try await session.start()

    #expect(permission.requestCount == 1)
    #expect(await broker.fetchCount == 1)
    #expect(transport.ephemeralKeys == ["ek_test_session"])
    #expect(transport.sentEvents.count == 1)

    let update = try eventObject(transport.sentEvents[0])
    let payload = try #require(update["session"] as? [String: Any])
    let audio = try #require(payload["audio"] as? [String: Any])
    let input = try #require(audio["input"] as? [String: Any])
    let turnDetection = try #require(
      input["turn_detection"] as? [String: Any]
    )

    #expect(update["type"] as? String == "session.update")
    #expect(payload["type"] as? String == "realtime")
    #expect(payload["model"] as? String == "gpt-realtime-2.1")
    #expect(payload["output_modalities"] as? [String] == ["audio"])
    #expect(turnDetection["type"] as? String == "semantic_vad")
    #expect(turnDetection["eagerness"] as? String == "low")
    #expect(turnDetection["create_response"] as? Bool == true)
    #expect(turnDetection["interrupt_response"] as? Bool == true)
    #expect(
      transport.sentEvents.contains {
        (try? eventType($0)) == "response.create"
      }
        == false
    )

    transport.emit(serverEvent: "session.updated")
    #expect(await events.next() == .listening)
  }

  @Test
  func mapsConversationAudioMuteBargeInAndTeardown() async throws {
    let transport = ScriptedRealtimeTransport()
    let session = OpenAIRealtimeVoiceSession(
      microphonePermission: StubMicrophonePermission(isGranted: true),
      broker: StubBrokerClient(),
      transport: transport
    )
    var events = session.events.makeAsyncIterator()
    try await session.start()

    transport.emit(serverEvent: "session.updated")
    #expect(await events.next() == .listening)

    transport.emit(serverEvent: "input_audio_buffer.speech_stopped")
    #expect(await events.next() == .thinking)

    transport.emit(serverEvent: "output_audio_buffer.started")
    #expect(await events.next() == .speaking)

    transport.emit(.outputEnergy(0.72))
    #expect(await events.next() == .audioEnergy(0.72))

    transport.emit(serverEvent: "input_audio_buffer.speech_started")
    #expect(await events.next() == .listening)
    #expect(
      try transport.sentEvents.suffix(2).map(eventType)
        == ["response.cancel", "output_audio_buffer.clear"]
    )

    await session.setMuted(true)
    #expect(transport.muteValues == [true])
    #expect(await events.next() == .muted)

    await session.setMuted(false)
    #expect(transport.muteValues == [true, false])
    #expect(await events.next() == .listening)

    await session.stop()
    #expect(transport.closeCount == 1)
    #expect(await events.next() == .ended)
  }

  @Test
  func rejectsStartBeforeFetchingASecretWhenMicrophoneIsDenied() async {
    let permission = StubMicrophonePermission(isGranted: false)
    let broker = StubBrokerClient()
    let transport = ScriptedRealtimeTransport()
    let session = OpenAIRealtimeVoiceSession(
      microphonePermission: permission,
      broker: broker,
      transport: transport
    )

    do {
      try await session.start()
      Issue.record("Expected microphone denial")
    } catch let failure as CompanionFailure {
      #expect(failure.kind == .microphoneDenied)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    #expect(await broker.fetchCount == 0)
    #expect(transport.ephemeralKeys.isEmpty)
  }

  @Test
  func aTransportFailureDoesNotBecomeAnEndedEvent() async throws {
    let transport = ScriptedRealtimeTransport()
    let session = OpenAIRealtimeVoiceSession(
      microphonePermission: StubMicrophonePermission(isGranted: true),
      broker: StubBrokerClient(),
      transport: transport
    )
    var events = session.events.makeAsyncIterator()
    try await session.start()
    let failure = CompanionFailure(
      kind: .network,
      message: "The voice connection was lost."
    )

    transport.emit(.failed(failure))
    #expect(await events.next() == .failed(failure))

    await session.stop()
    #expect(transport.closeCount == 1)
  }
}

@MainActor
private final class StubMicrophonePermission: MicrophonePermissionPort {
  private let isGranted: Bool
  private(set) var requestCount = 0

  init(isGranted: Bool) {
    self.isGranted = isGranted
  }

  func requestAccess() async -> Bool {
    requestCount += 1
    return isGranted
  }
}

private actor StubBrokerClient: BrokerClientPort {
  private(set) var fetchCount = 0

  func fetchClientSecret() async throws -> EphemeralClientSecret {
    fetchCount += 1
    return EphemeralClientSecret(
      value: "ek_test_session",
      expiresAt: 1_900_000_000
    )
  }
}

@MainActor
private final class ScriptedRealtimeTransport: RealtimeTransportPort {
  let events: AsyncStream<RealtimeTransportEvent>

  private let continuation: AsyncStream<RealtimeTransportEvent>.Continuation
  private(set) var ephemeralKeys: [String] = []
  private(set) var sentEvents: [Data] = []
  private(set) var muteValues: [Bool] = []
  private(set) var closeCount = 0

  init() {
    let pair = AsyncStream<RealtimeTransportEvent>.makeStream()
    events = pair.stream
    continuation = pair.continuation
  }

  func connect(ephemeralKey: String) async throws {
    ephemeralKeys.append(ephemeralKey)
  }

  func send(_ event: Data) throws {
    sentEvents.append(event)
  }

  func setMuted(_ isMuted: Bool) {
    muteValues.append(isMuted)
  }

  func close() {
    closeCount += 1
  }

  func emit(_ event: RealtimeTransportEvent) {
    continuation.yield(event)
  }

  func emit(serverEvent type: String) {
    continuation.yield(
      .serverMessage(Data(#"{"type":"\#(type)"}"#.utf8))
    )
  }
}

private func eventObject(_ data: Data) throws -> [String: Any] {
  let object = try JSONSerialization.jsonObject(with: data)
  return try #require(object as? [String: Any])
}

private func eventType(_ data: Data) throws -> String {
  let object = try eventObject(data)
  return try #require(object["type"] as? String)
}
