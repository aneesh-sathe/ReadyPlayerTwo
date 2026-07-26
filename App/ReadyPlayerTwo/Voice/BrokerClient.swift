import Foundation

struct EphemeralClientSecret: Equatable, Sendable {
  let value: String
  let expiresAt: Int
}

enum BrokerClientError: Error, Equatable, Sendable {
  case missingConfiguration(String)
  case invalidOrigin
  case invalidResponse
  case unsuccessfulResponse(Int)
  case malformedSecret
}

protocol HTTPDataClient: Sendable {
  func data(for request: URLRequest) async throws -> (
    Data,
    HTTPURLResponse
  )
}

actor URLSessionHTTPDataClient: HTTPDataClient {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func data(for request: URLRequest) async throws -> (
    Data,
    HTTPURLResponse
  ) {
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw BrokerClientError.invalidResponse
    }
    return (data, response)
  }
}

protocol BrokerClientPort: Sendable {
  func fetchClientSecret() async throws -> EphemeralClientSecret
}

struct BrokerClient: BrokerClientPort, Sendable {
  private static let originKey = "READYPLAYERTWO_BROKER_ORIGIN"
  private static let bearerKey = "READYPLAYERTWO_BROKER_BEARER"

  private let endpoint: URL
  private let bearer: String
  private let httpClient: any HTTPDataClient

  init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    httpClient: any HTTPDataClient = URLSessionHTTPDataClient()
  ) throws {
    guard
      let rawOrigin = environment[Self.originKey],
      !rawOrigin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw BrokerClientError.missingConfiguration(Self.originKey)
    }
    guard
      let bearer = environment[Self.bearerKey],
      !bearer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw BrokerClientError.missingConfiguration(Self.bearerKey)
    }
    guard
      let origin = URL(string: rawOrigin),
      Self.isAllowedBrokerOrigin(origin),
      let endpoint = URL(
        string: "/v1/realtime/client-secret",
        relativeTo: origin
      )?.absoluteURL
    else {
      throw BrokerClientError.invalidOrigin
    }

    self.endpoint = endpoint
    self.bearer = bearer
    self.httpClient = httpClient
  }

  func fetchClientSecret() async throws -> EphemeralClientSecret {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue(
      "Bearer \(bearer)",
      forHTTPHeaderField: "Authorization"
    )

    let (data, response) = try await httpClient.data(for: request)
    guard (200..<300).contains(response.statusCode) else {
      throw BrokerClientError.unsuccessfulResponse(response.statusCode)
    }

    let payload: SecretPayload
    do {
      payload = try JSONDecoder().decode(SecretPayload.self, from: data)
    } catch {
      throw BrokerClientError.malformedSecret
    }
    guard !payload.value.isEmpty else {
      throw BrokerClientError.malformedSecret
    }
    return EphemeralClientSecret(
      value: payload.value,
      expiresAt: payload.expiresAt
    )
  }

  private static func isAllowedBrokerOrigin(_ url: URL) -> Bool {
    guard
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      url.user == nil,
      url.password == nil,
      url.query == nil,
      url.fragment == nil,
      let host = url.host(percentEncoded: false)?.lowercased()
    else {
      return false
    }

    return host == "localhost"
      || host == "127.0.0.1"
      || host == "::1"
  }
}

private struct SecretPayload: Decodable {
  let value: String
  let expiresAt: Int

  enum CodingKeys: String, CodingKey {
    case value
    case expiresAt = "expires_at"
  }
}
