import Foundation

enum RealtimeCallClientError: Error, Equatable, Sendable {
  case invalidEndpoint
  case unsuccessfulResponse(Int)
  case malformedAnswer
}

protocol RealtimeCallClient: Sendable {
  func exchangeOffer(
    _ offer: String,
    ephemeralKey: String
  ) async throws -> String
}

struct OpenAIRealtimeCallClient: RealtimeCallClient, Sendable {
  private let endpoint: URL
  private let httpClient: any HTTPDataClient

  init(
    endpoint: URL? = URL(
      string: "https://api.openai.com/v1/realtime/calls"
    ),
    httpClient: any HTTPDataClient = URLSessionHTTPDataClient()
  ) throws {
    guard let endpoint else {
      throw RealtimeCallClientError.invalidEndpoint
    }
    self.endpoint = endpoint
    self.httpClient = httpClient
  }

  func exchangeOffer(
    _ offer: String,
    ephemeralKey: String
  ) async throws -> String {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.httpBody = Data(offer.utf8)
    request.setValue(
      "Bearer \(ephemeralKey)",
      forHTTPHeaderField: "Authorization"
    )
    request.setValue(
      "application/sdp",
      forHTTPHeaderField: "Content-Type"
    )

    let (data, response) = try await httpClient.data(for: request)
    guard (200..<300).contains(response.statusCode) else {
      throw RealtimeCallClientError.unsuccessfulResponse(
        response.statusCode
      )
    }
    guard
      let answer = String(data: data, encoding: .utf8),
      !answer.isEmpty
    else {
      throw RealtimeCallClientError.malformedAnswer
    }
    return answer
  }
}
