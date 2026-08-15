import AVFoundation
import Foundation

protocol LocalWhisperTranscribing: Sendable {
    func transcribeAudioFile(at url: URL) async throws -> String
}

actor LocalSpeechToTextService: SpeechToTextProviding {
    private let engine: any LocalWhisperTranscribing
    private let fallbackService: (any SpeechToTextProviding)?
    private let modelName: String

    init(
        engine: any LocalWhisperTranscribing,
        fallbackService: (any SpeechToTextProviding)? = nil,
        modelName: String = AIModelConfiguration.defaultLocalTranscriptionModel
    ) {
        self.engine = engine
        self.fallbackService = fallbackService
        self.modelName = modelName
    }

    func transcribe(_ recording: RecordedAudioFile) async throws -> SpeechTranscription {
        try Task.checkCancellation()
        guard recording.duration.isFinite, recording.duration > 0 else {
            throw SpeechToTextError.invalidAudio
        }

        let clock = ContinuousClock()
        let start = clock.now

        do {
            let transcribedText = try await engine.transcribeAudioFile(at: recording.url)
            let latency = start.duration(to: clock.now)
            let trimmedText = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                throw SpeechToTextError.emptyTranscript
            }

            return SpeechTranscription(
                text: trimmedText,
                model: modelName,
                usedFallback: false,
                latency: latency,
                recordedDuration: recording.duration,
                usage: SpeechTranscriptionUsage(
                    audioSeconds: recording.duration,
                    totalTokens: nil,
                    inputTokens: nil,
                    outputTokens: nil,
                    cost: 0.0
                )
            )
        } catch is CancellationError {
            throw SpeechToTextError.transport(.cancelled)
        } catch let error as SpeechToTextError {
            if let fallbackService {
                return try await fallbackService.transcribe(recording)
            }
            throw error
        } catch {
            if let fallbackService {
                return try await fallbackService.transcribe(recording)
            }
            throw SpeechToTextError.localTranscriptionFailed(error.localizedDescription)
        }
    }
}
