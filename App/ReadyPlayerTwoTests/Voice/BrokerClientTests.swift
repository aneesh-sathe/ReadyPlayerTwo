import Foundation
import Testing

@testable import ReadyPlayerTwo

@Suite(.serialized)
struct BrokerClientTests {
  @Test
  func requestsShortLivedSecretUsingOnlyBrokerConfiguration() async throws {
    let responseURL = try #require(
      URL(string: "http://127.0.0.1:43120/v1/realtime/client-secret")
    )
    let response = try #require(
      HTTPURLResponse(
        url: responseURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )
    )
    let httpClient = RecordingHTTPDataClient(
      data: Data(
        """
        {"value":"ephemeral-test-value","expires_at":1900000000}
        """.utf8
      ),
      response: response
    )
    let client = try BrokerClient(
      environment: [
        "OPENAI_API_KEY": "must-never-enter-the-request",
        "READYPLAYERTWO_BROKER_BEARER": "launch-bearer",
        "READYPLAYERTWO_BROKER_ORIGIN": "http://127.0.0.1:43120",
      ],
      httpClient: httpClient
    )

    let secret = try await client.fetchClientSecret()
    let requests = await httpClient.requests
    let request = try #require(requests.first)

    #expect(secret.value == "ephemeral-test-value")
    #expect(secret.expiresAt == 1_900_000_000)
    #expect(requests.count == 1)
    #expect(request.httpMethod == "POST")
    #expect(
      request.url?.absoluteString
        == "http://127.0.0.1:43120/v1/realtime/client-secret"
    )
    #expect(
      request.value(forHTTPHeaderField: "Authorization")
        == "Bearer launch-bearer"
    )
    #expect(
      request.allHTTPHeaderFields?.values.contains(
        "must-never-enter-the-request"
      )
        == false
    )
    #expect(request.httpBody == nil)
  }
}

private actor RecordingHTTPDataClient: HTTPDataClient {
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
