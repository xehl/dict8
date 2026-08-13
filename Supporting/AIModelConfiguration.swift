import Foundation

nonisolated struct AIModelPair: Equatable, Sendable {
    let primary: String
    let fallback: String
}

nonisolated struct AIModelConfiguration: Equatable, Sendable {
    let transcriptionModel: String
    let transcriptionFallbackModel: String
    /// Approved exception (AGENTS.md §4, PRD.md §8): cleanup uses OpenRouter's
    /// Auto Router (Beta track) as its sole explicit model attempt instead of
    /// a pinned primary model plus one dict8-side fallback.
    let cleanupModel: String

    static let phaseZeroVerified = AIModelConfiguration(
        transcriptionModel: "openai/whisper-large-v3",
        transcriptionFallbackModel: "google/chirp-3",
        cleanupModel: "openrouter/auto-beta"
    )

    var transcription: AIModelPair {
        AIModelPair(primary: transcriptionModel, fallback: transcriptionFallbackModel)
    }
}
