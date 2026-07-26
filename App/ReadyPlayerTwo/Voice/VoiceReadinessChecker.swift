import Foundation

protocol VoiceReadinessChecking: Sendable {
  func check() async -> VoiceReadiness
}

struct LoopbackVoiceReadinessChecker:
  VoiceReadinessChecking,
  Sendable
{
  private static let originKey =
    "READYPLAYERTWO_BROKER_ORIGIN"
  private static let configuredKey =
    "READYPLAYERTWO_VOICE_CONFIGURED"

  private let environment: [String: String]
  private let httpClient: any HTTPDataClient

  init(
    environment: [String: String] =
      ProcessInfo.processInfo.environment,
    httpClient: any HTTPDataClient = URLSessionHTTPDataClient()
  ) {
    self.environment = environment
    self.httpClient = httpClient
  }

  func check() async -> VoiceReadiness {
    guard
      let endpoint = Self.healthEndpoint(
        from: environment[Self.originKey]
      )
    else {
      return .brokerUnavailable
    }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "GET"
    request.timeoutInterval = 1

    do {
      let (data, response) = try await httpClient.data(for: request)
      guard
        (200..<300).contains(response.statusCode),
        let health = try? JSONDecoder().decode(
          BrokerHealthPayload.self,
          from: data
        ),
        health.status == "ok"
      else {
        return .brokerUnavailable
      }

      switch health.voice {
      case "configured":
        return environment[Self.configuredKey] == "1"
          ? .ready
          : .notConfigured
      case "not_configured":
        return .notConfigured
      default:
        return .brokerUnavailable
      }
    } catch {
      return .brokerUnavailable
    }
  }

  private static func healthEndpoint(
    from rawOrigin: String?
  ) -> URL? {
    guard
      let rawOrigin,
      let origin = URL(string: rawOrigin),
      let scheme = origin.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      origin.user == nil,
      origin.password == nil,
      origin.query == nil,
      origin.fragment == nil,
      origin.path.isEmpty || origin.path == "/",
      let host = origin.host(percentEncoded: false)?.lowercased(),
      host == "localhost" || host == "127.0.0.1" || host == "::1"
    else {
      return nil
    }

    return URL(string: "/health", relativeTo: origin)?
      .absoluteURL
  }
}

private struct BrokerHealthPayload: Decodable {
  let status: String
  let voice: String
}
