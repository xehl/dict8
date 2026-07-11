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
        XCTAssertNotEqual(
            configuration.cleanupModel,
            configuration.cleanupFallbackModel
        )
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
