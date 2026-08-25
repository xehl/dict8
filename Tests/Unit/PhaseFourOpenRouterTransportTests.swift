import XCTest

@testable import dict8

@MainActor
final class PhaseFourOpenRouterTransportTests: XCTestCase {
    func testDevelopmentOverrideCanBeRetrievedWithoutKeychainAccess() async throws {
        let expected = "generated-\(UUID().uuidString)"
        let store = SystemAPIKeyStore(environment: ["OPENROUTER_API_KEY": "  \(expected)  "])

        let key = try await store.apiKey()

        XCTAssertEqual(key, expected)
    }

    func testSuccessAuthenticatesAndEnforcesRoutingPolicy() async throws {
        let secret = "generated-\(UUID().uuidString)"
        let transport = StubOpenRouterTransport(outcomes: [.response(status: 200, body: successBody)])
        let client = makeClient(key: secret, transport: transport)

        let response = try await client.execute(
            syntheticRequest(),
            models: models,
            deadline: .seconds(1)
        )
        let capturedRequests = await transport.requests()
        let sent = try XCTUnwrap(capturedRequests.first)
        let body = try jsonObject(sent.httpBody)
        let provider = try XCTUnwrap(body["provider"] as? [String: Any])

        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer \(secret)")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Session-ID"), "fixed-session")
        XCTAssertEqual(sent.url?.path, "/api/v1/chat/completions")
        XCTAssertEqual(body["model"] as? String, models.primary)
        XCTAssertEqual(provider["zdr"] as? Bool, true)
        let maxLatency = try XCTUnwrap(provider["preferred_max_latency"] as? [String: Any])
        XCTAssertEqual(maxLatency["p90"] as? Double, 1.5)
        let minThroughput = try XCTUnwrap(provider["preferred_min_throughput"] as? [String: Any])
        XCTAssertEqual(minThroughput["p90"] as? Double, 60)
        XCTAssertNil(provider["allow_fallbacks"])
        XCTAssertEqual(body["synthetic_text"] as? String, syntheticContent)
        XCTAssertEqual(response.model, models.primary)
        XCTAssertEqual(response.attemptNumber, 1)
        XCTAssertFalse(response.usedFallback)
    }

    func testTranscriptionReliesOnAccountPrivacyWithoutUnsupportedRequestZDR() async throws {
        let transport = StubOpenRouterTransport(
            outcomes: [.response(status: 200, body: successBody)]
        )
        let client = makeClient(transport: transport)
        let body = try JSONSerialization.data(withJSONObject: [
            "input_audio": ["data": "synthetic", "format": "m4a"],
        ])

        _ = try await client.execute(
            OpenRouterRequest(endpoint: .transcription, body: body),
            models: models,
            deadline: .seconds(1)
        )

        let requests = await transport.requests()
        let sent = try XCTUnwrap(requests.first)
        let sentBody = try jsonObject(sent.httpBody)
        XCTAssertNil(sentBody["provider"])
        XCTAssertEqual(sentBody["model"] as? String, models.primary)
    }

    func testMissingKeyPreventsNetworkRequest() async throws {
        let transport = StubOpenRouterTransport(outcomes: [])
        let client = OpenRouterClient(
            apiKeyStore: StubAPIKeyStore(result: .failure(.missingKey)),
            transport: transport,
            fallbackDelay: { .zero }
        )

        await assertClientError(.missingAPIKey) {
            try await client.execute(
                syntheticRequest(),
                models: models,
                deadline: .seconds(1)
            )
        }
        let requestCount = await transport.requests().count
        XCTAssertEqual(requestCount, 0)
    }

    func testPermanentHTTPFailuresDoNotUseFallback() async throws {
        let cases: [(Int, String?, OpenRouterClientError)] = [
            (400, "invalid_request", .invalidRequest),
            (401, "authentication", .authentication),
            (402, "payment_required", .insufficientCredits),
            (403, "permission_denied", .forbidden),
            (404, "not_found", .modelNotFound),
            (413, "payload_too_large", .payloadTooLarge),
            (415, "unsupported_media_type", .unsupportedMedia),
            (422, "invalid_request", .invalidRequest),
        ]

        for (status, errorType, expected) in cases {
            let transport = StubOpenRouterTransport(outcomes: [
                .response(status: status, body: errorBody(errorType: errorType)),
            ])
            let client = makeClient(transport: transport)

            await assertClientError(expected) {
                try await client.execute(
                    syntheticRequest(),
                    models: models,
                    deadline: .seconds(1)
                )
            }
            let requestCount = await transport.requests().count
            XCTAssertEqual(requestCount, 1, "HTTP \(status)")
        }
    }

    func testEligibleHTTPFailuresUseExactlyOneExplicitModelFallback() async throws {
        for status in [408, 429, 500, 502, 503, 504] {
            let transport = StubOpenRouterTransport(outcomes: [
                .response(status: status, body: errorBody(errorType: nil)),
                .response(status: 200, body: successBody),
            ])
            let client = makeClient(transport: transport)

            let response = try await client.execute(
                syntheticRequest(),
                models: models,
                deadline: .seconds(1)
            )
            let requests = await transport.requests()
            let firstBody = try jsonObject(requests[0].httpBody)
            let secondBody = try jsonObject(requests[1].httpBody)

            XCTAssertEqual(requests.count, 2, "HTTP \(status)")
            XCTAssertEqual(firstBody["model"] as? String, models.primary)
            XCTAssertEqual(secondBody["model"] as? String, models.fallback)
            XCTAssertEqual(response.model, models.fallback)
            XCTAssertTrue(response.usedFallback)
        }
    }

    func testNetworkInterruptionUsesFallbackOnce() async throws {
        let transport = StubOpenRouterTransport(outcomes: [
            .urlError(.networkConnectionLost),
            .response(status: 200, body: successBody),
        ])
        let client = makeClient(transport: transport)

        let response = try await client.execute(
            syntheticRequest(),
            models: models,
            deadline: .seconds(1)
        )

        XCTAssertTrue(response.usedFallback)
        let requestCount = await transport.requests().count
        XCTAssertEqual(requestCount, 2)
    }

    func testExhausted503ReportsZDRUnavailable() async throws {
        let transport = StubOpenRouterTransport(outcomes: [
            .response(status: 503, body: errorBody(errorType: "provider_overloaded")),
            .response(status: 503, body: errorBody(errorType: "provider_unavailable")),
        ])
        let client = makeClient(transport: transport)

        await assertClientError(.zdrUnavailable) {
            try await client.execute(
                syntheticRequest(),
                models: models,
                deadline: .seconds(1)
            )
        }
        let requestCount = await transport.requests().count
        XCTAssertEqual(requestCount, 2)
    }

    func testRetryAfterDeltaSecondsIsObservedBeforeFallback() async throws {
        let sleeper = RecordingSleeper()
        let transport = StubOpenRouterTransport(outcomes: [
            .response(
                status: 429,
                headers: ["Retry-After": "0.25"],
                body: errorBody(errorType: "rate_limit_exceeded")
            ),
            .response(status: 200, body: successBody),
        ])
        let client = makeClient(transport: transport, sleeper: sleeper)

        _ = try await client.execute(
            syntheticRequest(),
            models: models,
            deadline: .seconds(1)
        )

        let durations = await sleeper.durations()
        XCTAssertEqual(durations, [.milliseconds(250)])
    }

    func testRetryAfterHTTPDateIsObservedBeforeFallback() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let retryDate = now.addingTimeInterval(1)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
        let sleeper = RecordingSleeper()
        let transport = StubOpenRouterTransport(outcomes: [
            .response(
                status: 503,
                headers: ["Retry-After": formatter.string(from: retryDate)],
                body: errorBody(errorType: "provider_overloaded")
            ),
            .response(status: 200, body: successBody),
        ])
        let client = makeClient(
            transport: transport,
            sleeper: sleeper,
            wallClockNow: { now }
        )

        _ = try await client.execute(
            syntheticRequest(),
            models: models,
            deadline: .seconds(2)
        )

        let durations = await sleeper.durations()
        XCTAssertEqual(durations, [.seconds(1)])
    }

    func testRetryAfterThatConsumesDeadlineDoesNotStartFallback() async throws {
        let sleeper = RecordingSleeper()
        let transport = StubOpenRouterTransport(outcomes: [
            .response(
                status: 429,
                headers: ["Retry-After": "10"],
                body: errorBody(errorType: "rate_limit_exceeded")
            ),
        ])
        let client = makeClient(transport: transport, sleeper: sleeper)

        await assertClientError(.deadlineExceeded) {
            try await client.execute(
                syntheticRequest(),
                models: models,
                deadline: .seconds(1)
            )
        }
        let durations = await sleeper.durations()
        let requestCount = await transport.requests().count
        XCTAssertEqual(durations, [])
        XCTAssertEqual(requestCount, 1)
    }

    func testStageDeadlineCancelsActiveTransportAndDoesNotFallback() async throws {
        let transport = StubOpenRouterTransport(outcomes: [.waitForCancellation])
        let client = makeClient(transport: transport)

        await assertClientError(.deadlineExceeded) {
            try await client.execute(
                syntheticRequest(),
                models: models,
                deadline: .milliseconds(20)
            )
        }
        let requestCount = await transport.requests().count
        XCTAssertEqual(requestCount, 1)
    }

    func testTaskCancellationDoesNotUseFallback() async throws {
        let transport = StubOpenRouterTransport(outcomes: [.waitForCancellation])
        let client = makeClient(transport: transport)
        let task = Task {
            try await client.execute(
                syntheticRequest(),
                models: models,
                deadline: .seconds(5)
            )
        }

        while await transport.requests().isEmpty {
            await Task.yield()
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch let error as OpenRouterClientError {
            XCTAssertEqual(error, .cancelled)
        }
        let requestCount = await transport.requests().count
        XCTAssertEqual(requestCount, 1)
    }

    func testAutomaticMultiModelRoutingIsRejectedLocally() async throws {
        let transport = StubOpenRouterTransport(outcomes: [])
        let client = makeClient(transport: transport)
        let body = try JSONSerialization.data(withJSONObject: [
            "models": [models.primary, models.fallback],
            "synthetic_text": syntheticContent,
        ])

        await assertClientError(.invalidRequest) {
            try await client.execute(
                OpenRouterRequest(endpoint: .chatCompletions, body: body),
                models: models,
                deadline: .seconds(1)
            )
        }
        let requestCount = await transport.requests().count
        XCTAssertEqual(requestCount, 0)
    }

    func testSingleModelExecuteSendsAutoRouterPluginAndMakesExactlyOneAttempt() async throws {
        let secret = "generated-\(UUID().uuidString)"
        let transport = StubOpenRouterTransport(outcomes: [.response(status: 200, body: successBody)])
        let client = makeClient(key: secret, transport: transport)

        let response = try await client.execute(
            syntheticRequest(),
            model: "openrouter/auto",
            autoRouter: AutoRouterSettings(costTier: .low),
            deadline: .seconds(1)
        )
        let capturedRequests = await transport.requests()
        let sent = try XCTUnwrap(capturedRequests.first)
        let body = try jsonObject(sent.httpBody)
        let provider = try XCTUnwrap(body["provider"] as? [String: Any])
        let plugins = try XCTUnwrap(body["plugins"] as? [[String: Any]])

        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer \(secret)")
        XCTAssertEqual(body["model"] as? String, "openrouter/auto")
        XCTAssertEqual(provider["zdr"] as? Bool, true)
        XCTAssertEqual(plugins.first?["id"] as? String, "auto-router")
        XCTAssertEqual(plugins.first?["cost_tier"] as? String, "low")
        XCTAssertEqual(response.model, "openrouter/auto")
        XCTAssertEqual(response.attemptNumber, 1)
        XCTAssertEqual(capturedRequests.count, 1)
    }

    func testSingleModelExecuteSendsAutoBetaRouterPluginForBetaSlug() async throws {
        let transport = StubOpenRouterTransport(outcomes: [.response(status: 200, body: successBody)])
        let client = makeClient(transport: transport)

        let response = try await client.execute(
            syntheticRequest(),
            model: "openrouter/auto-beta",
            autoRouter: AutoRouterSettings(costTier: .low),
            deadline: .seconds(1)
        )
        let capturedRequests = await transport.requests()
        let sent = try XCTUnwrap(capturedRequests.first)
        let body = try jsonObject(sent.httpBody)
        let plugins = try XCTUnwrap(body["plugins"] as? [[String: Any]])

        // The beta track only reads settings sent under its own plugin id;
        // sending "auto-router" here would be silently ignored by OpenRouter.
        XCTAssertEqual(body["model"] as? String, "openrouter/auto-beta")
        XCTAssertEqual(plugins.first?["id"] as? String, "auto-beta-router")
        XCTAssertEqual(plugins.first?["cost_tier"] as? String, "low")
        XCTAssertEqual(response.model, "openrouter/auto-beta")
    }

    func testSingleModelExecuteDoesNotFallBackOnEligibleTransientFailure() async throws {
        let transport = StubOpenRouterTransport(outcomes: [
            .response(status: 503, body: errorBody(errorType: "provider_overloaded")),
        ])
        let client = makeClient(transport: transport)

        await assertClientError(.zdrUnavailable) {
            try await client.execute(
                syntheticRequest(),
                model: "openrouter/auto",
                autoRouter: nil,
                deadline: .seconds(1)
            )
        }
        let requestCount = await transport.requests().count
        XCTAssertEqual(requestCount, 1)
    }

    func testSingleModelExecuteRejectsEmptyModelAndNonPositiveDeadline() async throws {
        let transport = StubOpenRouterTransport(outcomes: [])
        let client = makeClient(transport: transport)

        await assertClientError(.invalidRequest) {
            try await client.execute(
                syntheticRequest(),
                model: "",
                autoRouter: nil,
                deadline: .seconds(1)
            )
        }
        await assertClientError(.invalidRequest) {
            try await client.execute(
                syntheticRequest(),
                model: "openrouter/auto",
                autoRouter: nil,
                deadline: .zero
            )
        }
        let requestCount = await transport.requests().count
        XCTAssertEqual(requestCount, 0)
    }

    func testErrorsNeverExposeSecretRequestOrResponseContent() async throws {
        let secret = "secret-\(UUID().uuidString)"
        let echoedResponse = Data(
            "{\"error\":{\"code\":401,\"message\":\"\(syntheticContent) \(secret)\"}}"
                .utf8
        )
        let transport = StubOpenRouterTransport(outcomes: [
            .response(status: 401, body: echoedResponse),
        ])
        let client = makeClient(key: secret, transport: transport)

        do {
            _ = try await client.execute(
                syntheticRequest(),
                models: models,
                deadline: .seconds(1)
            )
            XCTFail("Expected authentication failure")
        } catch let error as OpenRouterClientError {
            let description = try XCTUnwrap(error.errorDescription)
            XCTAssertFalse(description.contains(secret))
            XCTAssertFalse(description.contains(syntheticContent))
        }
    }

    func testMalformedErrorBodyUsesSanitizedStatusClassification() async throws {
        let transport = StubOpenRouterTransport(outcomes: [
            .response(status: 401, body: Data("not-json \(syntheticContent)".utf8)),
        ])
        let client = makeClient(transport: transport)

        await assertClientError(.authentication) {
            try await client.execute(
                syntheticRequest(),
                models: models,
                deadline: .seconds(1)
            )
        }
    }

    private let models = AIModelPair(primary: "synthetic/primary", fallback: "synthetic/fallback")
    private let syntheticContent = "synthetic request content"
    private let successBody = Data("{\"ok\":true}".utf8)

    private func syntheticRequest() -> OpenRouterRequest {
        let body = try? JSONSerialization.data(withJSONObject: [
            "synthetic_text": syntheticContent,
        ])
        return OpenRouterRequest(
            endpoint: .chatCompletions,
            body: body ?? Data()
        )
    }

    private func errorBody(errorType: String?) -> Data {
        var error: [String: Any] = ["code": 500]
        if let errorType {
            error["metadata"] = ["error_type": errorType]
        }
        return (try? JSONSerialization.data(withJSONObject: ["error": error])) ?? Data()
    }

    private func makeClient(
        key: String = "generated-test-key",
        transport: StubOpenRouterTransport,
        sleeper: RecordingSleeper = RecordingSleeper(),
        wallClockNow: @escaping @Sendable () -> Date = Date.init
    ) -> OpenRouterClient {
        OpenRouterClient(
            apiKeyStore: StubAPIKeyStore(result: .success(key)),
            transport: transport,
            sleeper: sleeper,
            fallbackDelay: { .zero },
            wallClockNow: wallClockNow,
            dict8SessionID: "fixed-session"
        )
    }

    private func jsonObject(_ data: Data?) throws -> [String: Any] {
        let data = try XCTUnwrap(data)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func assertClientError(
        _ expected: OpenRouterClientError,
        operation: () async throws -> OpenRouterResponse
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)")
        } catch let error as OpenRouterClientError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
    }
}

private actor StubAPIKeyStore: APIKeyStoring {
    let result: Result<String, APIKeyStoreError>

    init(result: Result<String, APIKeyStoreError>) {
        self.result = result
    }

    func status() -> APIKeyStatus { .storedInKeychain }
    func apiKey() throws -> String { try result.get() }
    func save(_ key: String) {}
    func remove() {}
}

private actor StubOpenRouterTransport: OpenRouterURLTransporting {
    enum Outcome: Sendable {
        case response(status: Int, headers: [String: String] = [:], body: Data)
        case urlError(URLError.Code)
        case waitForCancellation
    }

    private var outcomes: [Outcome]
    private var capturedRequests: [URLRequest] = []

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func data(for request: URLRequest) async throws -> OpenRouterTransportResponse {
        capturedRequests.append(request)
        guard !outcomes.isEmpty else { throw URLError(.unknown) }
        let outcome = outcomes.removeFirst()

        switch outcome {
        case let .response(status, headers, body):
            let url = request.url ?? URL(fileURLWithPath: "/")
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            ) else {
                throw URLError(.badServerResponse)
            }
            return OpenRouterTransportResponse(data: body, response: response)
        case let .urlError(code):
            throw URLError(code)
        case .waitForCancellation:
            try await Task.sleep(for: .seconds(60))
            throw URLError(.timedOut)
        }
    }

    func requests() -> [URLRequest] { capturedRequests }
}

private actor RecordingSleeper: OpenRouterSleeping {
    private var recordedDurations: [Duration] = []

    func sleep(for duration: Duration) {
        recordedDurations.append(duration)
    }

    func durations() -> [Duration] { recordedDurations }
}
