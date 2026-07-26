import Foundation
import Testing

@testable import ReadyPlayerTwo

struct VoiceReadinessCheckerTests {
  @Test
  func configuredLocalHealthReportsReady() async throws {
    let endpoint = try #require(
      URL(string: "http://localhost:43120/health")
    )
    let response = try #require(
      HTTPURLResponse(
        url: endpoint,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )
    )
    let httpClient = HealthHTTPDataClient(
      data: Data(
        """
        {"status":"ok","voice":"configured"}
        """.utf8
      ),
      response: response
    )
    let checker = LoopbackVoiceReadinessChecker(
      environment: [
        "READYPLAYERTWO_BROKER_ORIGIN":
          "http://localhost:43120",
        "READYPLAYERTWO_VOICE_CONFIGURED": "1",
      ],
      httpClient: httpClient
    )

    #expect(await checker.check() == .ready)
  }

  @Test
  func localHealthReportsMissingVoiceWithoutCredentials() async throws {
    let endpoint = try #require(
      URL(string: "http://127.0.0.1:43120/health")
    )
    let response = try #require(
      HTTPURLResponse(
        url: endpoint,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )
    )
    let httpClient = HealthHTTPDataClient(
      data: Data(
        """
        {"status":"ok","voice":"not_configured"}
        """.utf8
      ),
      response: response
    )
    let checker = LoopbackVoiceReadinessChecker(
      environment: [
        "READYPLAYERTWO_BROKER_ORIGIN":
          "http://127.0.0.1:43120",
        "READYPLAYERTWO_BROKER_BEARER":
          "must-not-enter-health-request",
        "READYPLAYERTWO_VOICE_CONFIGURED": "0",
      ],
      httpClient: httpClient
    )

    let readiness = await checker.check()
    let requests = await httpClient.requests
    let request = try #require(requests.first)

    #expect(readiness == .notConfigured)
    #expect(requests.count == 1)
    #expect(
      request.url?.absoluteString
        == "http://127.0.0.1:43120/health"
    )
    #expect(request.httpMethod == "GET")
    #expect(request.httpBody == nil)
    #expect(
      request.value(forHTTPHeaderField: "Authorization") == nil
    )
  }

  @Test
  func healthProbeRejectsNonLoopbackOrigins() async throws {
    let endpoint = try #require(
      URL(string: "https://example.com/health")
    )
    let response = try #require(
      HTTPURLResponse(
        url: endpoint,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )
    )
    let httpClient = HealthHTTPDataClient(
      data: Data(
        """
        {"status":"ok","voice":"configured"}
        """.utf8
      ),
      response: response
    )
    let checker = LoopbackVoiceReadinessChecker(
      environment: [
        "READYPLAYERTWO_BROKER_ORIGIN":
          "https://example.com",
        "READYPLAYERTWO_VOICE_CONFIGURED": "1",
      ],
      httpClient: httpClient
    )

    #expect(await checker.check() == .brokerUnavailable)
    #expect(await httpClient.requests.isEmpty)
  }

  @Test
  func healthProbeRejectsRedirectedResponses() async throws {
    let remoteEndpoint = try #require(
      URL(string: "https://example.com/health")
    )
    let response = try #require(
      HTTPURLResponse(
        url: remoteEndpoint,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )
    )
    let httpClient = HealthHTTPDataClient(
      data: Data(
        """
        {"status":"ok","voice":"configured"}
        """.utf8
      ),
      response: response
    )
    let checker = LoopbackVoiceReadinessChecker(
      environment: [
        "READYPLAYERTWO_BROKER_ORIGIN":
          "http://127.0.0.1:43120",
        "READYPLAYERTWO_VOICE_CONFIGURED": "1",
      ],
      httpClient: httpClient
    )

    #expect(await checker.check() == .brokerUnavailable)
  }
}

private actor HealthHTTPDataClient: HTTPDataClient {
  private let data: Data
  private let response: HTTPURLResponse
  private(set) var requests: [URLRequest] = []

  init(data: Data, response: HTTPURLResponse) {
    self.data = data
    self.response = response
  }

  func data(for request: URLRequest) async throws -> (
    Data,
    HTTPURLResponse
  ) {
    requests.append(request)
    return (data, response)
  }
}
