import Foundation
import XCTest

@testable import dict8

private struct StubWhisperEngine: LocalWhisperTranscribing {
    let result: Result<String, Error>

    func transcribeAudioFile(at url: URL) async throws -> String {
        switch result {
        case let .success(text):
            return text
        case let .failure(error):
            throw error
        }
    }
}

private actor FallbackSTTStub: SpeechToTextProviding {
    var transcribeCallCount = 0
    let transcription: SpeechTranscription

    init(transcription: SpeechTranscription) {
        self.transcription = transcription
    }

    func transcribe(_ recording: RecordedAudioFile) async throws -> SpeechTranscription {
        transcribeCallCount += 1
        return transcription
    }
}

final class LocalSpeechToTextTests: XCTestCase {
    private func makeRecording(duration: TimeInterval = 3.5) -> RecordedAudioFile {
        RecordedAudioFile(
            url: URL(fileURLWithPath: "/tmp/sample.m4a"),
            duration: duration,
            sampleRate: 16000,
            channelCount: 1,
            bitRate: 32000
        )
    }

    func testLocalTranscriptionSuccess() async throws {
        let engine = StubWhisperEngine(result: .success("  hello world on device  \n"))
        let service = LocalSpeechToTextService(
            engine: engine,
            modelName: "distil-whisper/distil-large-v3"
        )

        let result = try await service.transcribe(makeRecording())

        XCTAssertEqual(result.text, "hello world on device")
        XCTAssertEqual(result.model, "distil-whisper/distil-large-v3")
        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.usage?.cost, 0.0)
        XCTAssertEqual(result.usage?.audioSeconds, 3.5)
    }

    func testLocalTranscriptionEmptyOutputThrowsError() async {
        let engine = StubWhisperEngine(result: .success("   \n\t  "))
        let service = LocalSpeechToTextService(engine: engine)

        do {
            _ = try await service.transcribe(makeRecording())
            XCTFail("Expected empty transcript error")
        } catch let error as SpeechToTextError {
            XCTAssertEqual(error, .emptyTranscript)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testLocalTranscriptionFailureTriggersFallback() async throws {
        struct CustomEngineError: Error, LocalizedError {
            var errorDescription: String? { "CoreML failure" }
        }

        let engine = StubWhisperEngine(result: .failure(CustomEngineError()))
        let fallbackTranscription = SpeechTranscription(
            text: "remote fallback text",
            model: "openai/whisper-large-v3",
            usedFallback: true,
            latency: .milliseconds(300),
            recordedDuration: 3.5,
            usage: nil
        )
        let fallbackService = FallbackSTTStub(transcription: fallbackTranscription)

        let service = LocalSpeechToTextService(
            engine: engine,
            fallbackService: fallbackService
        )

        let result = try await service.transcribe(makeRecording())

        XCTAssertEqual(result.text, "remote fallback text")
        XCTAssertEqual(result.model, "openai/whisper-large-v3")
        XCTAssertTrue(result.usedFallback)
        let callCount = await fallbackService.transcribeCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testLocalTranscriptionInvalidAudioDuration() async {
        let engine = StubWhisperEngine(result: .success("hello"))
        let service = LocalSpeechToTextService(engine: engine)

        do {
            _ = try await service.transcribe(makeRecording(duration: 0))
            XCTFail("Expected invalid audio error")
        } catch let error as SpeechToTextError {
            XCTAssertEqual(error, .invalidAudio)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
