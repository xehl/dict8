import Foundation
import XCTest

@testable import dict8

final class PhaseFiveSpeechToTextTests: XCTestCase {
    func testBuildsPortableM4ARequestAndDecodesUsage() async throws {
        let transport = SpeechTransportStub(
            result: .success(
                OpenRouterResponse(
                    data: Data(#"{"text":"  synthetic transcript\n","usage":{"seconds":12.5,"total_tokens":10,"input_tokens":7,"output_tokens":3,"cost":0.004}}"#.utf8),
                    model: models.primary,
                    attemptNumber: 1,
                    latency: .milliseconds(450)
                )
            )
        )
        let service = makeService(transport: transport, audio: Data([0x01, 0x02, 0x03]))

        let result = try await service.transcribe(recording())
        let executions = await transport.executions()
        let execution = try XCTUnwrap(executions.first)
        let body = try jsonObject(execution.request.body)
        let inputAudio = try XCTUnwrap(body["input_audio"] as? [String: Any])

        XCTAssertEqual(execution.request.endpoint, .transcription)
        XCTAssertEqual(execution.models, models)
        XCTAssertEqual(execution.deadline, .seconds(45))
        XCTAssertEqual(inputAudio["format"] as? String, "m4a")
        XCTAssertEqual(inputAudio["data"] as? String, Data([0x01, 0x02, 0x03]).base64EncodedString())
        XCTAssertEqual(body["language"] as? String, "en")
        XCTAssertEqual(body["temperature"] as? Double, 0)
        XCTAssertNil(body["response_format"])
        XCTAssertNil(body["model"])
        XCTAssertEqual(result.text, "synthetic transcript")
        XCTAssertEqual(result.recordedDuration, 12.5)
        XCTAssertEqual(result.model, models.primary)
        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.usage?.audioSeconds, 12.5)
        XCTAssertEqual(result.usage?.totalTokens, 10)
        XCTAssertEqual(result.usage?.cost, 0.004)
        XCTAssertEqual(result.coverageDiagnostic, .nominal)
    }

    func testUsageIsOptionalAndMalformedValuesDoNotRejectText() async throws {
        let response = OpenRouterResponse(
            data: Data(#"{"text":"valid","usage":{"seconds":-1,"cost":"unknown","total_tokens":4}}"#.utf8),
            model: models.primary,
            attemptNumber: 1,
            latency: .milliseconds(1)
        )
        let service = makeService(transport: SpeechTransportStub(result: .success(response)))

        let result = try await service.transcribe(recording())

        XCTAssertEqual(result.text, "valid")
        XCTAssertNil(result.usage?.audioSeconds)
        XCTAssertNil(result.usage?.cost)
        XCTAssertEqual(result.usage?.totalTokens, 4)
    }

    func testFallbackMetadataIsReportedWithoutChangingTranscriptContract() async throws {
        let response = OpenRouterResponse(
            data: Data(#"{"text":"fallback result"}"#.utf8),
            model: models.fallback,
            attemptNumber: 2,
            latency: .seconds(1)
        )
        let service = makeService(transport: SpeechTransportStub(result: .success(response)))

        let result = try await service.transcribe(recording())

        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(result.model, models.fallback)
        XCTAssertNil(result.usage)
    }

    func testCoverageFlagsProviderDurationMateriallyShorterThanRecording() {
        XCTAssertEqual(
            TranscriptionCoverageDiagnostic.assess(
                text: "synthetic transcript with enough words for a normal result",
                recordedDuration: 60,
                providerAudioSeconds: 42
            ),
            .providerDurationShort
        )
    }

    func testCoverageFlagsSparseLongTranscriptButDoesNotRejectIt() async throws {
        let response = OpenRouterResponse(
            data: Data(#"{"text":"short compressed result","usage":{"seconds":30}}"#.utf8),
            model: models.primary,
            attemptNumber: 1,
            latency: .milliseconds(1)
        )
        let service = makeService(
            transport: SpeechTransportStub(result: .success(response))
        )

        let result = try await service.transcribe(recording(duration: 30))

        XCTAssertEqual(result.text, "short compressed result")
        XCTAssertEqual(result.coverageDiagnostic, .sparseTranscript)
    }

    func testCoverageAllowsOrdinarySpeechDensity() {
        let words = Array(repeating: "synthetic", count: 30).joined(separator: " ")
        XCTAssertEqual(
            TranscriptionCoverageDiagnostic.assess(
                text: words,
                recordedDuration: 30,
                providerAudioSeconds: 30
            ),
            .nominal
        )
    }

    func testEmptySuccessfulTranscriptIsRejectedWithoutAnotherTransportAttempt() async throws {
        let transport = SpeechTransportStub(
            result: .success(
                OpenRouterResponse(
                    data: Data(#"{"text":" \n "}"#.utf8),
                    model: models.primary,
                    attemptNumber: 1,
                    latency: .zero
                )
            )
        )
        let service = makeService(transport: transport)

        await assertSpeechError(.emptyTranscript) {
            try await service.transcribe(recording())
        }
        let executionCount = await transport.executions().count
        XCTAssertEqual(executionCount, 1)
    }

    func testMalformedResponseIsRejected() async throws {
        let response = OpenRouterResponse(
            data: Data(#"{"usage":{"seconds":1}}"#.utf8),
            model: models.primary,
            attemptNumber: 1,
            latency: .zero
        )
        let service = makeService(transport: SpeechTransportStub(result: .success(response)))

        await assertSpeechError(.invalidResponse) {
            try await service.transcribe(recording())
        }
    }

    func testTransportErrorRemainsTypedAndContentFree() async throws {
        let service = makeService(
            transport: SpeechTransportStub(result: .failure(.authentication))
        )

        await assertSpeechError(.transport(.authentication)) {
            try await service.transcribe(recording())
        }
    }

    func testInvalidLocalAudioNeverCallsTransport() async throws {
        let transport = SpeechTransportStub(
            result: .failure(.networkFailure)
        )
        let service = makeService(transport: transport, audio: Data())

        await assertSpeechError(.invalidAudio) {
            try await service.transcribe(recording())
        }
        let executions = await transport.executions()
        XCTAssertTrue(executions.isEmpty)
    }

    private let models = AIModelPair(
        primary: "synthetic/primary",
        fallback: "synthetic/fallback"
    )

    private func makeService(
        transport: SpeechTransportStub,
        audio: Data = Data([0x01])
    ) -> OpenRouterSpeechToTextService {
        OpenRouterSpeechToTextService(
            transport: transport,
            models: models,
            fileLoader: { _ in audio }
        )
    }

    private func recording(duration: TimeInterval = 12.5) -> RecordedAudioFile {
        RecordedAudioFile(
            url: URL(fileURLWithPath: "/tmp/synthetic-phase-five.m4a"),
            duration: duration,
            sampleRate: 16_000,
            channelCount: 1,
            bitRate: 32_000
        )
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func assertSpeechError(
        _ expected: SpeechToTextError,
        operation: () async throws -> SpeechTranscription
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)")
        } catch let error as SpeechToTextError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
    }
}

private actor SpeechTransportStub: OpenRouterTransporting {
    struct Execution: Sendable {
        let request: OpenRouterRequest
        let models: AIModelPair
        let deadline: Duration
    }

    private let result: Result<OpenRouterResponse, OpenRouterClientError>
    private var captured: [Execution] = []

    init(result: Result<OpenRouterResponse, OpenRouterClientError>) {
        self.result = result
    }

    func execute(
        _ request: OpenRouterRequest,
        models: AIModelPair,
        deadline: Duration
    ) throws -> OpenRouterResponse {
        captured.append(Execution(request: request, models: models, deadline: deadline))
        return try result.get()
    }

    func executions() -> [Execution] { captured }
}
