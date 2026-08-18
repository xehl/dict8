import XCTest
@testable import dict8

@MainActor
final class PhaseZeroFoundationTests: XCTestCase {
    func testVerifiedModelsAreExplicitAndDistinct() {
        let configuration = AIModelConfiguration.phaseZeroVerified

        XCTAssertFalse(configuration.transcriptionModel.isEmpty)
        XCTAssertFalse(configuration.cleanupModel.isEmpty)
        XCTAssertNotEqual(
            configuration.transcriptionModel,
            configuration.transcriptionFallbackModel
        )
        // Cleanup is an approved exception to the pinned-model-plus-fallback
        // rule: it routes through OpenRouter's Auto Router (stable slug) as
        // a single explicit model attempt (AGENTS.md §4, PRD.md §8).
        XCTAssertEqual(configuration.cleanupModel, "openrouter/auto")
        XCTAssertEqual(configuration.localTranscriptionModel, "distil-whisper/distil-large-v3")
        XCTAssertTrue(AIModelConfiguration.fastCleanupCandidates.contains("meta-llama/llama-3.1-8b-instruct:nitro"))
        XCTAssertTrue(AIModelConfiguration.fastCleanupCandidates.contains("meta-llama/llama-3.2-3b-instruct"))
        XCTAssertTrue(AIModelConfiguration.fastCleanupCandidates.contains("openrouter/auto"))
    }

    func testFocusedElementSnapshotCarriesNoFieldValue() {
        let snapshot = FocusedElementSnapshot(
            bundleIdentifier: "com.example.editor",
            role: "AXTextField",
            subrole: "AXSecureTextField",
            isSecureTextField: true,
            diagnostic: "Synthetic fixture"
        )

        XCTAssertTrue(snapshot.isSecureTextField)
        XCTAssertEqual(snapshot.bundleIdentifier, "com.example.editor")
    }
}
