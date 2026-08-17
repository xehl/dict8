import AVFoundation
import Foundation
@preconcurrency import WhisperKit

protocol LocalWhisperTranscribing: Sendable {
    func transcribeAudioFile(at url: URL) async throws -> String
}

final class SystemWhisperEngine: LocalWhisperTranscribing, @unchecked Sendable {
    private var whisperKit: WhisperKit?
    private let lock = NSLock()
    private let modelName: String

    init(modelName: String = "distil-whisper_distil-large-v3") {
        self.modelName = modelName
    }

    private func getOrInitializeWhisperKit() async throws -> WhisperKit {
        if let existing = lock.withLock({ whisperKit }) {
            return existing
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsFolder = appSupport.appendingPathComponent("dict8/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsFolder, withIntermediateDirectories: true)

        let pipe = try await WhisperKit(
            model: modelName,
            modelFolder: modelsFolder.path,
            verbose: false,
            logLevel: .error
        )
        lock.withLock {
            self.whisperKit = pipe
        }
        return pipe
    }

    nonisolated func transcribeAudioFile(at url: URL) async throws -> String {
        do {
            let pipe = try await getOrInitializeWhisperKit()
            let results = try await pipe.transcribe(audioPath: url.path)
            let fullText = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return fullText
        } catch {
            throw SpeechToTextError.localTranscriptionFailed(error.localizedDescription)
        }
    }
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
