import Foundation

struct RealtimeVoiceConfiguration: Equatable, Sendable {
  let model: String
  let voice: String
  let instructions: String

  static let companionV1 = Self(
    model: "gpt-realtime-2.1",
    voice: "marin",
    instructions:
      """
      You are a warm, concise desktop companion. The person summoned you, \
      so follow their lead and keep the exchange natural. You have no \
      screen context in this version. Never claim to see their screen or \
      infer what app or document they are using.
      """
  )
}

struct EphemeralClientSecret: Equatable, Sendable {
  let value: String
  let expiresAt: Int
}

enum BrokerClientError: Error, Equatable, Sendable {
  case missingConfiguration(String)
  case invalidOrigin
  case invalidResponse
  case unsuccessfulResponse(statusCode: Int, code: String?)
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
  private let configuration: RealtimeVoiceConfiguration
  private let httpClient: any HTTPDataClient

  init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    configuration: RealtimeVoiceConfiguration = .companionV1,
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
    self.configuration = configuration
    self.httpClient = httpClient
  }

  func fetchClientSecret() async throws -> EphemeralClientSecret {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.httpBody = try JSONEncoder().encode(
      RequestedConfiguration(
        model: configuration.model,
        voice: configuration.voice
      )
    )
    request.setValue(
      "Bearer \(bearer)",
      forHTTPHeaderField: "Authorization"
    )
    request.setValue(
      "application/json",
      forHTTPHeaderField: "Content-Type"
    )

    let (data, response) = try await httpClient.data(for: request)
    guard (200..<300).contains(response.statusCode) else {
      let reportedCode = try? JSONDecoder().decode(
        BrokerFailurePayload.self,
        from: data
      ).error
      let stableCode =
        reportedCode.flatMap {
          Self.stableFailureCodes.contains($0) ? $0 : nil
        }
      throw BrokerClientError.unsuccessfulResponse(
        statusCode: response.statusCode,
        code: stableCode
      )
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

  private static let stableFailureCodes = Set([
    "upstream_authentication_failed",
    "upstream_rate_limited",
    "upstream_unavailable",
  ])
}

private struct SecretPayload: Decodable {
  let value: String
  let expiresAt: Int

  enum CodingKeys: String, CodingKey {
    case value
    case expiresAt = "expires_at"
  }
}

private struct RequestedConfiguration: Encodable {
  let model: String
  let voice: String
}

private struct BrokerFailurePayload: Decodable {
  let error: String
}
