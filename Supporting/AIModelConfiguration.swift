import Foundation

nonisolated struct AIModelPair: Equatable, Sendable {
    let primary: String
    let fallback: String
}

nonisolated struct AIModelConfiguration: Equatable, Sendable {
    let transcriptionModel: String
    let transcriptionFallbackModel: String
    /// Approved exception (AGENTS.md §4, PRD.md §8): cleanup uses OpenRouter's
    /// Auto Router (stable slug) as its sole explicit model attempt instead
    /// of a pinned primary model plus one dict8-side fallback.
    let cleanupModel: String
    let localTranscriptionModel: String

    static let defaultLocalTranscriptionModel = "distil-whisper/distil-large-v3"

    /// Fast cloud candidate models evaluated during benchmarking harness experimentation.
    static let fastCleanupCandidates: [String] = [
        "meta-llama/llama-3.1-8b-instruct:nitro",
        "google/gemini-2.5-flash-lite",
        "meta-llama/llama-3.2-3b-instruct",
        "qwen/qwen-2.5-7b-instruct",
        "openrouter/auto",
    ]

    static let phaseZeroVerified = AIModelConfiguration(
        transcriptionModel: "openai/whisper-large-v3",
        transcriptionFallbackModel: "google/chirp-3",
        cleanupModel: "meta-llama/llama-3.1-8b-instruct:nitro",
        localTranscriptionModel: defaultLocalTranscriptionModel
    )

    var transcription: AIModelPair {
        AIModelPair(primary: transcriptionModel, fallback: transcriptionFallbackModel)
    }
}
