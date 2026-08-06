import Foundation

nonisolated struct SpeechTranscriptionUsage: Equatable, Sendable {
    let audioSeconds: Double?
    let totalTokens: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let cost: Double?
}

nonisolated struct SpeechTranscription: Equatable, Sendable {
    let text: String
    let model: String
    let usedFallback: Bool
    let latency: Duration
    let recordedDuration: TimeInterval
    let usage: SpeechTranscriptionUsage?

    var coverageDiagnostic: TranscriptionCoverageDiagnostic {
        TranscriptionCoverageDiagnostic.assess(
            text: text,
            recordedDuration: recordedDuration,
            providerAudioSeconds: usage?.audioSeconds
        )
    }
}

nonisolated enum TranscriptionCoverageDiagnostic: String, Equatable, Sendable {
    case nominal
    case providerDurationShort
    case sparseTranscript

    var displayName: String {
        switch self {
        case .nominal: "Nominal"
        case .providerDurationShort: "Provider duration shorter than recording"
        case .sparseTranscript: "Unusually sparse transcript"
        }
    }

    static func assess(
        text: String,
        recordedDuration: TimeInterval,
        providerAudioSeconds: Double?
    ) -> Self {
        if let providerAudioSeconds,
           providerAudioSeconds.isFinite,
           recordedDuration.isFinite,
           recordedDuration > 0 {
            let tolerance = max(2, recordedDuration * 0.1)
            if providerAudioSeconds + tolerance < recordedDuration {
                return .providerDurationShort
            }
        }

        let effectiveDuration = providerAudioSeconds ?? recordedDuration
        guard effectiveDuration.isFinite, effectiveDuration >= 20 else {
            return .nominal
        }
        let wordCount = text.split(whereSeparator: { character in
            !character.isLetter && !character.isNumber
        }).count
        return Double(wordCount) / effectiveDuration < 1
            ? .sparseTranscript
            : .nominal
    }
}

nonisolated enum SpeechToTextError: Error, Equatable, LocalizedError, Sendable {
    case audioUnavailable
    case unsupportedAudioFormat
    case invalidAudio
    case requestEncodingFailed
    case invalidResponse
    case emptyTranscript
    case transport(OpenRouterClientError)

    var errorDescription: String? {
        switch self {
        case .audioUnavailable:
            "dict8 could not read the temporary audio recording."
        case .unsupportedAudioFormat:
            "The temporary recording has an unsupported audio format."
        case .invalidAudio:
            "The temporary audio recording is empty or invalid."
        case .requestEncodingFailed:
            "dict8 could not prepare the transcription request."
        case .invalidResponse:
            "OpenRouter returned an invalid transcription response."
        case .emptyTranscript:
            "OpenRouter returned an empty transcription."
        case let .transport(error):
            error.localizedDescription
        }
    }
}

nonisolated protocol SpeechToTextProviding: Sendable {
    func transcribe(_ recording: RecordedAudioFile) async throws -> SpeechTranscription
}

actor OpenRouterSpeechToTextService: SpeechToTextProviding {
    static let defaultDeadline: Duration = .seconds(45)
    static let temperature = 0.0

    private let transport: any OpenRouterTransporting
    private let models: AIModelPair
    private let deadline: Duration
    private let fileLoader: @Sendable (URL) throws -> Data

    init(
        transport: any OpenRouterTransporting,
        models: AIModelPair = AIModelConfiguration.phaseZeroVerified.transcription,
        deadline: Duration = OpenRouterSpeechToTextService.defaultDeadline,
        fileLoader: @escaping @Sendable (URL) throws -> Data = {
            try Data(contentsOf: $0, options: .mappedIfSafe)
        }
    ) {
        self.transport = transport
        self.models = models
        self.deadline = deadline
        self.fileLoader = fileLoader
    }

    func transcribe(_ recording: RecordedAudioFile) async throws -> SpeechTranscription {
        try Task.checkCancellation()
        guard recording.url.pathExtension.lowercased() == "m4a" else {
            throw SpeechToTextError.unsupportedAudioFormat
        }
        guard recording.duration.isFinite, recording.duration > 0 else {
            throw SpeechToTextError.invalidAudio
        }

        let audio: Data
        do {
            audio = try fileLoader(recording.url)
        } catch is CancellationError {
            throw SpeechToTextError.transport(.cancelled)
        } catch {
            throw SpeechToTextError.audioUnavailable
        }
        guard !audio.isEmpty else { throw SpeechToTextError.invalidAudio }
        try Task.checkCancellation()

        let body: Data
        do {
            body = try JSONEncoder().encode(
                TranscriptionRequest(
                    inputAudio: .init(
                        data: audio.base64EncodedString(),
                        format: "m4a"
                    ),
                    language: "en",
                    temperature: Self.temperature
                )
            )
        } catch {
            throw SpeechToTextError.requestEncodingFailed
        }

        let response: OpenRouterResponse
        do {
            response = try await transport.execute(
                OpenRouterRequest(endpoint: .transcription, body: body),
                models: models,
                deadline: deadline
            )
        } catch let error as OpenRouterClientError {
            throw SpeechToTextError.transport(error)
        } catch is CancellationError {
            throw SpeechToTextError.transport(.cancelled)
        } catch {
            throw SpeechToTextError.transport(.networkFailure)
        }

        let decoded: TranscriptionResponse
        do {
            decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: response.data)
        } catch {
            throw SpeechToTextError.invalidResponse
        }
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw SpeechToTextError.emptyTranscript }

        return SpeechTranscription(
            text: text,
            model: response.model,
            usedFallback: response.usedFallback,
            latency: response.latency,
            recordedDuration: recording.duration,
            usage: decoded.usage?.validated
        )
    }
}

nonisolated struct UnavailableSpeechToTextService: SpeechToTextProviding {
    func transcribe(_ recording: RecordedAudioFile) async throws -> SpeechTranscription {
        throw SpeechToTextError.transport(.invalidRequest)
    }
}

nonisolated private struct TranscriptionRequest: Encodable {
    struct InputAudio: Encodable {
        let data: String
        let format: String
    }

    let inputAudio: InputAudio
    let language: String
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case inputAudio = "input_audio"
        case language
        case temperature
    }
}

nonisolated private struct TranscriptionResponse: Decodable {
    struct Usage: Decodable {
        let seconds: Double?
        let totalTokens: Int?
        let inputTokens: Int?
        let outputTokens: Int?
        let cost: Double?

        enum CodingKeys: String, CodingKey {
            case seconds
            case totalTokens = "total_tokens"
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cost
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            seconds = try? container.decode(Double.self, forKey: .seconds)
            totalTokens = try? container.decode(Int.self, forKey: .totalTokens)
            inputTokens = try? container.decode(Int.self, forKey: .inputTokens)
            outputTokens = try? container.decode(Int.self, forKey: .outputTokens)
            cost = try? container.decode(Double.self, forKey: .cost)
        }

        var validated: SpeechTranscriptionUsage? {
            let result = SpeechTranscriptionUsage(
                audioSeconds: Self.nonnegativeFinite(seconds),
                totalTokens: Self.nonnegative(totalTokens),
                inputTokens: Self.nonnegative(inputTokens),
                outputTokens: Self.nonnegative(outputTokens),
                cost: Self.nonnegativeFinite(cost)
            )
            guard result.audioSeconds != nil
                    || result.totalTokens != nil
                    || result.inputTokens != nil
                    || result.outputTokens != nil
                    || result.cost != nil else {
                return nil
            }
            return result
        }

        private static func nonnegative(_ value: Int?) -> Int? {
            guard let value, value >= 0 else { return nil }
            return value
        }

        private static func nonnegativeFinite(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value >= 0 else { return nil }
            return value
        }
    }

    let text: String
    let usage: Usage?

    enum CodingKeys: String, CodingKey {
        case text
        case usage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        usage = try? container.decode(Usage.self, forKey: .usage)
    }
}
