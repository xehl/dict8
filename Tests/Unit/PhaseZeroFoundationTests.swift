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
        // Cleanup defaults to the pinned high-throughput Nitro model
        // meta-llama/llama-3.1-8b-instruct:nitro for sub-500ms cleanup latency
        // with auto-router and other fast models available as candidates.
        XCTAssertEqual(configuration.cleanupModel, "meta-llama/llama-3.1-8b-instruct:nitro")
        XCTAssertEqual(configuration.localTranscriptionModel, "distil-whisper/distil-large-v3")
        XCTAssertTrue(AIModelConfiguration.fastCleanupCandidates.contains("meta-llama/llama-3.1-8b-instruct:nitro"))
        XCTAssertTrue(AIModelConfiguration.fastCleanupCandidates.contains("google/gemini-2.5-flash-lite"))
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
