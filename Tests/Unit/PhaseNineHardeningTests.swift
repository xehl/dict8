import Foundation
import XCTest

@testable import dict8

@MainActor
final class PhaseNineHardeningTests: XCTestCase {
    func testMetricsPersistOnlyAggregateCountersCostsAndLatency() throws {
        let suiteName = "PhaseNineMetrics.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SystemUsageMetricsStore(defaults: defaults)

        _ = try store.recordStarted(audioSeconds: 60)
        _ = try store.recordCompletion(
            DictationMetricEvent(
                outcome: .success,
                transcriptionLatency: .seconds(2),
                cleanupLatency: .seconds(1),
                totalLatency: .seconds(4),
                transcriptionCost: 0.003,
                cleanupCost: 0.000_02,
                usedRawCleanupFallback: true,
                issueCategory: .cleanupRawFallback,
                cleanupFailureReason: .transportDeadlineExceeded
            )
        )
        _ = try store.recordStarted(audioSeconds: 30)
        _ = try store.recordCompletion(
            DictationMetricEvent(
                outcome: .failure,
                transcriptionLatency: .seconds(3),
                cleanupLatency: nil,
                totalLatency: .seconds(3),
                transcriptionCost: nil,
                cleanupCost: nil,
                usedRawCleanupFallback: false,
                issueCategory: .transcriptionFailure,
                cleanupFailureReason: nil
            )
        )
        _ = try store.recordStarted(audioSeconds: 10)

        let reloaded = SystemUsageMetricsStore(defaults: defaults)
        let metrics = reloaded.snapshot
        XCTAssertEqual(metrics.requestCount, 3)
        XCTAssertEqual(metrics.successCount, 1)
        XCTAssertEqual(metrics.failureCount, 1)
        XCTAssertEqual(metrics.cancellationCount, 1)
        XCTAssertEqual(metrics.audioMinutes, 100.0 / 60.0, accuracy: 0.000_001)
        XCTAssertEqual(metrics.totalTranscriptionCost, 0.003, accuracy: 0.000_001)
        XCTAssertEqual(metrics.totalCleanupCost, 0.000_02, accuracy: 0.000_001)
        XCTAssertEqual(metrics.averageTranscriptionLatencySeconds, 2.5)
        XCTAssertEqual(metrics.averageCleanupLatencySeconds, 1)
        XCTAssertEqual(metrics.averagePipelineLatencySeconds, 3.5)
        XCTAssertEqual(metrics.p50TranscriptionLatencySeconds, 2)
        XCTAssertEqual(metrics.p95TranscriptionLatencySeconds, 3)
        XCTAssertEqual(metrics.p50CleanupLatencySeconds, 1)
        XCTAssertEqual(metrics.p95CleanupLatencySeconds, 1)
        XCTAssertEqual(metrics.cleanupFallbackCount, 1)
        XCTAssertEqual(metrics.lastIssueCategory, .transcriptionFailure)
    }

    func testLatencyPercentilesEstimateOverRetainedSampleWindow() throws {
        let suiteName = "PhaseNinePercentiles.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SystemUsageMetricsStore(defaults: defaults)

        for second in 1...100 {
            _ = try store.recordStarted(audioSeconds: 1)
            _ = try store.recordCompletion(
                DictationMetricEvent(
                    outcome: .success,
                    transcriptionLatency: .seconds(second),
                    cleanupLatency: nil,
                    totalLatency: .seconds(second),
                    transcriptionCost: nil,
                    cleanupCost: nil,
                    usedRawCleanupFallback: false,
                    issueCategory: nil,
                    cleanupFailureReason: nil
                )
            )
        }

        let metrics = store.snapshot
        XCTAssertEqual(metrics.transcriptionLatencyCount, 100)
        XCTAssertEqual(metrics.p50TranscriptionLatencySeconds, 50)
        XCTAssertEqual(metrics.p95TranscriptionLatencySeconds, 95)
        XCTAssertNil(metrics.p50CleanupLatencySeconds)
        XCTAssertNil(metrics.p95CleanupLatencySeconds)
    }

    func testLatencySampleWindowStaysBoundedAndKeepsMostRecentSamples() throws {
        let suiteName = "PhaseNineSampleCap.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SystemUsageMetricsStore(defaults: defaults)

        let sampleCount = UsageMetricsSnapshot.latencySampleCap + 50
        for second in 1...sampleCount {
            _ = try store.recordStarted(audioSeconds: 1)
            _ = try store.recordCompletion(
                DictationMetricEvent(
                    outcome: .success,
                    transcriptionLatency: .seconds(second),
                    cleanupLatency: nil,
                    totalLatency: .seconds(second),
                    transcriptionCost: nil,
                    cleanupCost: nil,
                    usedRawCleanupFallback: false,
                    issueCategory: nil,
                    cleanupFailureReason: nil
                )
            )
        }

        let metrics = store.snapshot
        XCTAssertEqual(metrics.transcriptionLatencySamples.count, UsageMetricsSnapshot.latencySampleCap)
        // The oldest 50 samples (seconds 1...50) should have been evicted;
        // the retained window starts at second 51.
        XCTAssertEqual(metrics.transcriptionLatencySamples.min(), 51)
        XCTAssertEqual(metrics.transcriptionLatencySamples.max(), Double(sampleCount))
        XCTAssertTrue(metrics.isValid)
    }

    func testInvalidMetricsResetWithoutTouchingOtherDefaults() throws {
        let suiteName = "PhaseNineInvalidMetrics.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: AppState.enabledDefaultsKey)
        defaults.set(Data("not valid metrics".utf8), forKey: SystemUsageMetricsStore.defaultsKey)

        let store = SystemUsageMetricsStore(defaults: defaults)

        XCTAssertEqual(store.status, .resetAfterInvalidData)
        XCTAssertEqual(store.snapshot, UsageMetricsSnapshot())
        XCTAssertTrue(defaults.bool(forKey: AppState.enabledDefaultsKey))
        XCTAssertNil(defaults.data(forKey: SystemUsageMetricsStore.defaultsKey))
    }

    func testMetricsBlobCannotContainSyntheticUserContent() throws {
        let suiteName = "PhaseNinePrivacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SystemUsageMetricsStore(defaults: defaults)
        _ = try store.recordStarted(audioSeconds: 12)
        _ = try store.recordCompletion(
            DictationMetricEvent(
                outcome: .success,
                transcriptionLatency: .milliseconds(100),
                cleanupLatency: .milliseconds(50),
                totalLatency: .milliseconds(200),
                transcriptionCost: nil,
                cleanupCost: nil,
                usedRawCleanupFallback: false,
                issueCategory: nil,
                cleanupFailureReason: nil
            )
        )

        let data = try XCTUnwrap(defaults.data(forKey: SystemUsageMetricsStore.defaultsKey))
        let persisted = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(persisted.contains("synthetic private transcript sentinel"))
        XCTAssertFalse(persisted.localizedCaseInsensitiveContains("authorization"))
        XCTAssertFalse(persisted.localizedCaseInsensitiveContains("clipboard"))
        XCTAssertFalse(persisted.localizedCaseInsensitiveContains("audio path"))
    }

    func testStaleSweepDeletesOnlyOldRegularM4AFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(component: "PhaseNineSweep-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(component: "dict8-recordings", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldM4A = directory.appending(component: "old.m4a")
        let freshM4A = directory.appending(component: "fresh.m4a")
        let oldWAV = directory.appending(component: "old.wav")
        let nestedDirectory = directory.appending(component: "nested", directoryHint: .isDirectory)
        let nestedM4A = nestedDirectory.appending(component: "nested.m4a")
        try Data([0x01]).write(to: oldM4A)
        try Data([0x02]).write(to: freshM4A)
        try Data([0x03]).write(to: oldWAV)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try Data([0x04]).write(to: nestedM4A)
        let oldDate = Date().addingTimeInterval(-30 * 60)
        for url in [oldM4A, oldWAV, nestedM4A] {
            try FileManager.default.setAttributes(
                [.modificationDate: oldDate],
                ofItemAtPath: url.path
            )
        }
        let maintenance = SystemTemporaryAudioMaintenance(temporaryRoot: root)

        let removed = try await maintenance.sweepStaleRecordings(
            olderThan: Date().addingTimeInterval(-15 * 60)
        )

        XCTAssertEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldM4A.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshM4A.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldWAV.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedM4A.path))
    }

    func testMissingRecordingDirectoryIsAValidCleanSweep() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(component: "PhaseNineMissingSweep-\(UUID().uuidString)")
        let maintenance = SystemTemporaryAudioMaintenance(temporaryRoot: root)

        let removed = try await maintenance.sweepStaleRecordings(olderThan: Date())

        XCTAssertEqual(removed, 0)
    }
}
