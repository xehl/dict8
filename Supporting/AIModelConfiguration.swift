import Foundation

nonisolated struct AIModelPair: Equatable, Sendable {
    let primary: String
    let fallback: String
}

nonisolated struct AIModelConfiguration: Equatable, Sendable {
    let transcriptionModel: String
    let transcriptionFallbackModel: String
    let cleanupModel: String
    let cleanupFallbackModel: String

    static let phaseZeroVerified = AIModelConfiguration(
        transcriptionModel: "openai/whisper-large-v3",
        transcriptionFallbackModel: "google/chirp-3",
        cleanupModel: "google/gemini-2.5-flash-lite",
        cleanupFallbackModel: "anthropic/claude-haiku-4.5"
    )

    var transcription: AIModelPair {
        AIModelPair(primary: transcriptionModel, fallback: transcriptionFallbackModel)
    }

    var cleanup: AIModelPair {
        AIModelPair(primary: cleanupModel, fallback: cleanupFallbackModel)
    }
}
