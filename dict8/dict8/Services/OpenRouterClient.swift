import Foundation

enum OpenRouterEndpoint: String, Sendable {
    case transcription = "audio/transcriptions"
    case chatCompletions = "chat/completions"
}

struct OpenRouterRequest: Sendable {
    let endpoint: OpenRouterEndpoint
    let body: Data
}

struct OpenRouterResponse: Sendable {
    let data: Data
    let model: String
    let attemptNumber: Int
    let latency: Duration

    var usedFallback: Bool { attemptNumber == 2 }
}

enum OpenRouterClientError: Error, Equatable, LocalizedError, Sendable {
    case missingAPIKey
    case credentialUnavailable
    case invalidRequest
    case authentication
    case insufficientCredits
    case forbidden
    case modelNotFound
    case rateLimited
    case payloadTooLarge
    case providerUnavailable
    case zdrUnavailable
    case serverFailure
    case networkFailure
    case invalidResponse
    case deadlineExceeded
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "An OpenRouter API key is required."
        case .credentialUnavailable:
            "dict8 could not read the OpenRouter API key."
        case .invalidRequest:
            "dict8 could not create a valid OpenRouter request."
        case .authentication:
            "OpenRouter rejected the configured API key."
        case .insufficientCredits:
            "The OpenRouter account has insufficient credits."
        case .forbidden:
            "OpenRouter refused this request."
        case .modelNotFound:
            "The configured OpenRouter model is unavailable."
        case .rateLimited:
            "OpenRouter rate-limited the request."
        case .payloadTooLarge:
            "The OpenRouter request is too large."
        case .providerUnavailable:
            "The OpenRouter provider is temporarily unavailable."
        case .zdrUnavailable:
            "No Zero Data Retention route is currently available."
        case .serverFailure:
            "OpenRouter could not complete the request."
        case .networkFailure:
            "dict8 could not reach OpenRouter."
        case .invalidResponse:
            "OpenRouter returned an invalid response."
        case .deadlineExceeded:
            "OpenRouter did not complete the request in time."
        case .cancelled:
            "The OpenRouter request was cancelled."
        }
    }
}

struct OpenRouterTransportResponse: @unchecked Sendable {
    let data: Data
    let response: HTTPURLResponse
}

protocol OpenRouterURLTransporting: Sendable {
    func data(for request: URLRequest) async throws -> OpenRouterTransportResponse
}

final class SystemOpenRouterURLTransport: OpenRouterURLTransporting, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> OpenRouterTransportResponse {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterClientError.invalidResponse
        }
        return OpenRouterTransportResponse(data: data, response: httpResponse)
    }
}

protocol OpenRouterSleeping: Sendable {
    func sleep(for duration: Duration) async throws
}

struct TaskOpenRouterSleeper: OpenRouterSleeping {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

protocol OpenRouterTransporting: Sendable {
    func execute(
        _ request: OpenRouterRequest,
        models: AIModelPair,
        deadline: Duration
    ) async throws -> OpenRouterResponse
}

final class OpenRouterClient: OpenRouterTransporting, Sendable {
    private let baseURL: URL?
    private let apiKeyStore: any APIKeyStoring
    private let transport: any OpenRouterURLTransporting
    private let sleeper: any OpenRouterSleeping
    private let fallbackDelay: @Sendable () -> Duration
    private let wallClockNow: @Sendable () -> Date

    init(
        baseURL: URL? = URL(string: "https://openrouter.ai/api/v1/"),
        apiKeyStore: any APIKeyStoring,
        transport: any OpenRouterURLTransporting = SystemOpenRouterURLTransport(),
        sleeper: any OpenRouterSleeping = TaskOpenRouterSleeper(),
        fallbackDelay: @escaping @Sendable () -> Duration = {
            .milliseconds(150 + Int.random(in: 0 ... 100))
        },
        wallClockNow: @escaping @Sendable () -> Date = Date.init
    ) {
        self.baseURL = baseURL
        self.apiKeyStore = apiKeyStore
        self.transport = transport
        self.sleeper = sleeper
        self.fallbackDelay = fallbackDelay
        self.wallClockNow = wallClockNow
    }

    func execute(
        _ request: OpenRouterRequest,
        models: AIModelPair,
        deadline: Duration
    ) async throws -> OpenRouterResponse {
        guard deadline > .zero,
              !models.primary.isEmpty,
              !models.fallback.isEmpty,
              models.primary != models.fallback else {
            throw OpenRouterClientError.invalidRequest
        }

        let apiKey = try await loadAPIKey()
        let clock = ContinuousClock()
        let executionStartedAt = clock.now
        let deadlineInstant = clock.now.advanced(by: deadline)
        let selectedModels = [models.primary, models.fallback]

        for (index, model) in selectedModels.enumerated() {
            try Task.checkCancellation()
            let remaining = clock.now.duration(to: deadlineInstant)
            guard remaining > .zero else {
                throw OpenRouterClientError.deadlineExceeded
            }

            let urlRequest = try makeURLRequest(
                request,
                model: model,
                apiKey: apiKey
            )
            do {
                let result = try await perform(urlRequest, timeout: remaining)
                guard (200 ... 299).contains(result.response.statusCode) else {
                    throw classifiedFailure(from: result)
                }
                return OpenRouterResponse(
                    data: result.data,
                    model: model,
                    attemptNumber: index + 1,
                    latency: executionStartedAt.duration(to: clock.now)
                )
            } catch let failure as AttemptFailure {
                guard index == 0, failure.fallbackEligible else {
                    if failure.statusCode == 503 {
                        throw OpenRouterClientError.zdrUnavailable
                    }
                    throw failure.error
                }

                let delay = failure.retryAfter ?? fallbackDelay()
                try await waitBeforeFallback(
                    delay,
                    deadlineInstant: deadlineInstant,
                    clock: clock
                )
            } catch is CancellationError {
                throw OpenRouterClientError.cancelled
            } catch let error as OpenRouterClientError {
                if error == .cancelled || error == .deadlineExceeded || error == .invalidRequest {
                    throw error
                }
                guard index == 0, error == .networkFailure else {
                    throw error
                }
                try await waitBeforeFallback(
                    fallbackDelay(),
                    deadlineInstant: deadlineInstant,
                    clock: clock
                )
            } catch let error as URLError {
                if error.code == .cancelled || Task.isCancelled {
                    throw OpenRouterClientError.cancelled
                }
                guard index == 0 else {
                    throw OpenRouterClientError.networkFailure
                }
                try await waitBeforeFallback(
                    fallbackDelay(),
                    deadlineInstant: deadlineInstant,
                    clock: clock
                )
            } catch {
                guard index == 0 else {
                    throw OpenRouterClientError.networkFailure
                }
                try await waitBeforeFallback(
                    fallbackDelay(),
                    deadlineInstant: deadlineInstant,
                    clock: clock
                )
            }
        }

        throw OpenRouterClientError.invalidResponse
    }

    private func loadAPIKey() async throws -> String {
        do {
            return try await apiKeyStore.apiKey()
        } catch APIKeyStoreError.missingKey {
            throw OpenRouterClientError.missingAPIKey
        } catch {
            throw OpenRouterClientError.credentialUnavailable
        }
    }

    private func makeURLRequest(
        _ request: OpenRouterRequest,
        model: String,
        apiKey: String
    ) throws -> URLRequest {
        guard let baseURL,
              var body = try JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              body["models"] == nil,
              body["route"] == nil else {
            throw OpenRouterClientError.invalidRequest
        }

        var provider = body["provider"] as? [String: Any] ?? [:]
        if body["provider"] != nil, !(body["provider"] is [String: Any]) {
            throw OpenRouterClientError.invalidRequest
        }
        provider["zdr"] = true
        body["provider"] = provider
        body["model"] = model

        guard JSONSerialization.isValidJSONObject(body) else {
            throw OpenRouterClientError.invalidRequest
        }

        var urlRequest = URLRequest(
            url: baseURL.appendingPathComponent(request.endpoint.rawValue)
        )
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    private func perform(
        _ request: URLRequest,
        timeout: Duration
    ) async throws -> OpenRouterTransportResponse {
        try await withThrowingTaskGroup(of: TimedResult.self) { group in
            group.addTask { [transport] in
                .response(try await transport.data(for: request))
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return .deadline
            }
            defer { group.cancelAll() }

            guard let first = try await group.next() else {
                throw OpenRouterClientError.invalidResponse
            }
            switch first {
            case let .response(response):
                return response
            case .deadline:
                throw OpenRouterClientError.deadlineExceeded
            }
        }
    }

    private func classifiedFailure(
        from result: OpenRouterTransportResponse
    ) -> AttemptFailure {
        let status = result.response.statusCode
        let errorType = decodedErrorType(from: result.data)
        let error: OpenRouterClientError

        switch errorType {
        case "authentication": error = .authentication
        case "payment_required": error = .insufficientCredits
        case "permission_denied": error = .forbidden
        case "not_found": error = .modelNotFound
        case "rate_limit_exceeded": error = .rateLimited
        case "payload_too_large": error = .payloadTooLarge
        case "provider_overloaded", "provider_unavailable": error = .providerUnavailable
        case "server", "unmapped": error = .serverFailure
        case "timeout": error = .deadlineExceeded
        default: error = errorForStatus(status)
        }

        return AttemptFailure(
            error: error,
            statusCode: status,
            fallbackEligible: Self.fallbackEligibleStatusCodes.contains(status)
                && Self.fallbackEligibleErrors.contains(error),
            retryAfter: retryAfter(from: result.response)
        )
    }

    private func errorForStatus(_ status: Int) -> OpenRouterClientError {
        switch status {
        case 400, 422: .invalidRequest
        case 401: .authentication
        case 402: .insufficientCredits
        case 403: .forbidden
        case 404: .modelNotFound
        case 408, 504: .deadlineExceeded
        case 413: .payloadTooLarge
        case 429: .rateLimited
        case 500: .serverFailure
        case 502, 503: .providerUnavailable
        default: .invalidResponse
        }
    }

    private func decodedErrorType(from data: Data) -> String? {
        do {
            return try JSONDecoder().decode(ErrorEnvelope.self, from: data).error.metadata?.errorType
        } catch {
            // Error bodies can contain user content, so malformed or unknown fields are discarded.
            return nil
        }
    }

    private func retryAfter(from response: HTTPURLResponse) -> Duration? {
        guard response.statusCode == 429 || response.statusCode == 503,
              let value = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        if let seconds = Double(value), seconds >= 0 {
            return .milliseconds(Int64(seconds * 1_000))
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
        guard let date = formatter.date(from: value) else { return nil }
        return .milliseconds(Int64(max(0, date.timeIntervalSince(wallClockNow())) * 1_000))
    }

    private func waitBeforeFallback<C: Clock>(
        _ delay: Duration,
        deadlineInstant: C.Instant,
        clock: C
    ) async throws where C.Duration == Duration {
        try Task.checkCancellation()
        guard delay >= .zero,
              delay < clock.now.duration(to: deadlineInstant) else {
            throw OpenRouterClientError.deadlineExceeded
        }
        do {
            try await sleeper.sleep(for: delay)
        } catch is CancellationError {
            throw OpenRouterClientError.cancelled
        }
    }

    private static let fallbackEligibleStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]
    private static let fallbackEligibleErrors: [OpenRouterClientError] = [
        .rateLimited,
        .providerUnavailable,
        .serverFailure,
        .deadlineExceeded,
    ]
}

private enum TimedResult: Sendable {
    case response(OpenRouterTransportResponse)
    case deadline
}

private struct AttemptFailure: Error, Sendable {
    let error: OpenRouterClientError
    let statusCode: Int
    let fallbackEligible: Bool
    let retryAfter: Duration?
}

private struct ErrorEnvelope: Decodable {
    struct Body: Decodable {
        struct Metadata: Decodable {
            let errorType: String?

            enum CodingKeys: String, CodingKey {
                case errorType = "error_type"
            }
        }

        let metadata: Metadata?
    }

    let error: Body
}
