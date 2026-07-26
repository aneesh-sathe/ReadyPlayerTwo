import Foundation
import Testing

@testable import ReadyPlayerTwo

@Suite(.serialized)
struct OpenAIRealtimeCallClientTests {
  @Test
  func postsOfferAsSDPUsingOnlyTheEphemeralSecret() async throws {
    let responseURL = try #require(
      URL(string: "https://api.openai.com/v1/realtime/calls")
    )
    let response = try #require(
      HTTPURLResponse(
        url: responseURL,
        statusCode: 201,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/sdp"]
      )
    )
    let httpClient = CallRecordingHTTPDataClient(
      data: Data("v=0\r\nanswer".utf8),
      response: response
    )
    let client = try OpenAIRealtimeCallClient(httpClient: httpClient)

    let answer = try await client.exchangeOffer(
      "v=0\r\noffer",
      ephemeralKey: "ek_test_short_lived"
    )
    let request = try #require(await httpClient.requests.first)

    #expect(answer == "v=0\r\nanswer")
    #expect(request.url == responseURL)
    #expect(request.httpMethod == "POST")
    #expect(
      request.value(forHTTPHeaderField: "Authorization")
        == "Bearer ek_test_short_lived"
    )
    #expect(
      request.value(forHTTPHeaderField: "Content-Type")
        == "application/sdp"
    )
    #expect(request.httpBody == Data("v=0\r\noffer".utf8))
  }
}

private actor CallRecordingHTTPDataClient: HTTPDataClient {
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
