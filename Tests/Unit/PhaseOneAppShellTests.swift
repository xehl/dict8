import ServiceManagement
import XCTest

@testable import dict8

@MainActor
final class PhaseOneAppShellTests: XCTestCase {
    func testEnabledStateDefaultsOnAndPersistsChanges() throws {
        let suiteName = "PhaseOneAppShellTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initialState = AppState(defaults: defaults)
        XCTAssertTrue(initialState.isEnabled)
        XCTAssertEqual(initialState.status, .idle)

        initialState.setEnabled(false)
        let restoredState = AppState(defaults: defaults)

        XCTAssertFalse(restoredState.isEnabled)
        XCTAssertEqual(restoredState.status, .disabled)
    }

    func testCoordinatorUpdatesEnabledStateAndPresentsHUD() {
        let suiteName = "PhaseOneAppShellTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(defaults: defaults)
        let hud = FakeRecordingHUD()
        let coordinator = AppCoordinator(
            state: state,
            apiKeyStore: FakeAPIKeyStore(),
            launchAtLoginService: FakeLaunchAtLoginService(),
            hud: hud
        )

        coordinator.setEnabled(false)
        coordinator.previewHUD()

        XCTAssertEqual(state.status, .disabled)
        XCTAssertEqual(hud.previewDurations, [.seconds(2)])
    }

    func testDevelopmentAPIKeyOverrideTakesPrecedenceWithoutReadingKeychain() async throws {
        let store = SystemAPIKeyStore(environment: ["OPENROUTER_API_KEY": "development-override"])

        let status = try await store.status()

        XCTAssertEqual(status, .developmentOverride)
    }

    func testLaunchAtLoginStatusTracksRequestedState() {
        XCTAssertFalse(LaunchAtLoginStatus.notRegistered.isRequested)
        XCTAssertTrue(LaunchAtLoginStatus.enabled.isRequested)
        XCTAssertTrue(LaunchAtLoginStatus.requiresApproval.isRequested)
        XCTAssertFalse(LaunchAtLoginStatus.unavailable.isRequested)
    }

    func testLaunchAtLoginAttemptsRegistrationWhenServiceIsNotFound() {
        XCTAssertTrue(
            SystemLaunchAtLoginService.shouldAttemptRegistration(for: .notFound)
        )
        XCTAssertTrue(
            SystemLaunchAtLoginService.shouldAttemptRegistration(for: .notRegistered)
        )
        XCTAssertFalse(
            SystemLaunchAtLoginService.shouldAttemptRegistration(for: .enabled)
        )
        XCTAssertFalse(
            SystemLaunchAtLoginService.shouldAttemptRegistration(for: .requiresApproval)
        )
    }

    func testErrorsAreContentFree() {
        let messages = [
            AppShellError.apiKeyStatusUnavailable,
            .apiKeyInvalid,
            .apiKeySaveFailed,
            .apiKeyRemovalFailed,
            .launchAtLoginUpdateFailed,
        ].compactMap(\.errorDescription)

        XCTAssertEqual(messages.count, 5)
        XCTAssertTrue(messages.allSatisfy { !$0.contains("development-override") })
    }
}

private actor FakeAPIKeyStore: APIKeyStoring {
    func status() -> APIKeyStatus { .missing }
    func save(_ key: String) {}
    func remove() {}
}

@MainActor
private final class FakeLaunchAtLoginService: LaunchAtLoginControlling {
    private(set) var status: LaunchAtLoginStatus = .notRegistered

    func setEnabled(_ isEnabled: Bool) {
        status = isEnabled ? .enabled : .notRegistered
    }

    func openSystemSettings() {}
}

@MainActor
private final class FakeRecordingHUD: RecordingHUDPresenting {
    private(set) var previewDurations: [Duration] = []

    func showPreview(for duration: Duration) {
        previewDurations.append(duration)
    }

    func hide() {}
}
