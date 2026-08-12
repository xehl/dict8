import Foundation

nonisolated enum DictationMetricOutcome: String, Codable, Equatable, Sendable {
    case success
    case failure
}

nonisolated enum DictationIssueCategory: String, Codable, Equatable, Sendable {
    case transcriptionFailure
    case transcriptionFallback
    case cleanupRawFallback
    case focusChanged
    case pasteFailure
    case temporaryAudioCleanupFailure
    case recordingCueFailure

    var displayName: String {
        switch self {
        case .transcriptionFailure: "Transcription failure"
        case .transcriptionFallback: "Transcription fallback used"
        case .cleanupRawFallback: "Raw transcript fallback"
        case .focusChanged: "Copied because focus changed"
        case .pasteFailure: "Paste failure"
        case .temporaryAudioCleanupFailure: "Temporary audio cleanup failure"
        case .recordingCueFailure: "Recording cue failure"
        }
    }
}

nonisolated struct DictationMetricEvent: Equatable, Sendable {
    let outcome: DictationMetricOutcome
    let transcriptionLatency: Duration?
    let cleanupLatency: Duration?
    let totalLatency: Duration
    let transcriptionCost: Double?
    let cleanupCost: Double?
    let usedRawCleanupFallback: Bool
    let issueCategory: DictationIssueCategory?
}

nonisolated struct UsageMetricsSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    var version = Self.schemaVersion
    var requestCount = 0
    var successCount = 0
    var failureCount = 0
    var totalAudioSeconds = 0.0
    var totalTranscriptionCost = 0.0
    var totalCleanupCost = 0.0
    var totalTranscriptionLatencySeconds = 0.0
    var transcriptionLatencyCount = 0
    var totalCleanupLatencySeconds = 0.0
    var cleanupLatencyCount = 0
    var totalPipelineLatencySeconds = 0.0
    var pipelineLatencyCount = 0
    var cleanupFallbackCount = 0
    var lastIssueCategory: DictationIssueCategory?

    var cancellationCount: Int {
        max(0, requestCount - successCount - failureCount)
    }

    var audioMinutes: Double {
        totalAudioSeconds / 60
    }

    var totalReportedCost: Double {
        totalTranscriptionCost + totalCleanupCost
    }

    var averageTranscriptionLatencySeconds: Double? {
        average(totalTranscriptionLatencySeconds, count: transcriptionLatencyCount)
    }

    var averageCleanupLatencySeconds: Double? {
        average(totalCleanupLatencySeconds, count: cleanupLatencyCount)
    }

    var averagePipelineLatencySeconds: Double? {
        average(totalPipelineLatencySeconds, count: pipelineLatencyCount)
    }

    mutating func recordStarted(audioSeconds: Double) {
        requestCount += 1
        if Self.validNumber(audioSeconds) {
            totalAudioSeconds += audioSeconds
        }
    }

    mutating func recordCompletion(_ event: DictationMetricEvent) {
        switch event.outcome {
        case .success: successCount += 1
        case .failure: failureCount += 1
        }
        if let seconds = Self.validSeconds(event.transcriptionLatency) {
            totalTranscriptionLatencySeconds += seconds
            transcriptionLatencyCount += 1
        }
        if let seconds = Self.validSeconds(event.cleanupLatency) {
            totalCleanupLatencySeconds += seconds
            cleanupLatencyCount += 1
        }
        if let seconds = Self.validSeconds(event.totalLatency) {
            totalPipelineLatencySeconds += seconds
            pipelineLatencyCount += 1
        }
        if let cost = event.transcriptionCost, Self.validNumber(cost) {
            totalTranscriptionCost += cost
        }
        if let cost = event.cleanupCost, Self.validNumber(cost) {
            totalCleanupCost += cost
        }
        if event.usedRawCleanupFallback {
            cleanupFallbackCount += 1
        }
        if let issueCategory = event.issueCategory {
            lastIssueCategory = issueCategory
        }
    }

    var isValid: Bool {
        version == Self.schemaVersion
            && requestCount >= 0
            && successCount >= 0
            && failureCount >= 0
            && successCount + failureCount <= requestCount
            && transcriptionLatencyCount >= 0
            && cleanupLatencyCount >= 0
            && pipelineLatencyCount >= 0
            && cleanupFallbackCount >= 0
            && Self.validNumber(totalAudioSeconds)
            && Self.validNumber(totalTranscriptionCost)
            && Self.validNumber(totalCleanupCost)
            && Self.validNumber(totalTranscriptionLatencySeconds)
            && Self.validNumber(totalCleanupLatencySeconds)
            && Self.validNumber(totalPipelineLatencySeconds)
    }

    private func average(_ total: Double, count: Int) -> Double? {
        guard count > 0 else { return nil }
        return total / Double(count)
    }

    private static func validSeconds(_ duration: Duration?) -> Double? {
        guard let duration else { return nil }
        let seconds = seconds(duration)
        return validNumber(seconds) ? seconds : nil
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private static func validNumber(_ value: Double) -> Bool {
        value.isFinite && value >= 0
    }
}

enum MetricsStoreStatus: Equatable, Sendable {
    case available
    case resetAfterInvalidData
    case persistenceFailed

    var displayName: String {
        switch self {
        case .available: "Available"
        case .resetAfterInvalidData: "Reset after invalid stored data"
        case .persistenceFailed: "Persistence unavailable"
        }
    }
}

enum MetricsStoreError: Error, Equatable, Sendable {
    case encodingFailed
}

@MainActor
protocol UsageMetricsRecording: AnyObject {
    var snapshot: UsageMetricsSnapshot { get }
    var status: MetricsStoreStatus { get }
    @discardableResult
    func recordStarted(audioSeconds: Double) throws -> UsageMetricsSnapshot
    @discardableResult
    func recordCompletion(_ event: DictationMetricEvent) throws -> UsageMetricsSnapshot
}

@MainActor
final class SystemUsageMetricsStore: UsageMetricsRecording {
    static let defaultsKey = "dict8.metrics.v1"

    private let defaults: UserDefaults
    private(set) var snapshot: UsageMetricsSnapshot
    private(set) var status: MetricsStoreStatus

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.defaultsKey) else {
            snapshot = UsageMetricsSnapshot()
            status = .available
            return
        }
        if let decoded = try? JSONDecoder().decode(UsageMetricsSnapshot.self, from: data),
           decoded.isValid {
            snapshot = decoded
            status = .available
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
            snapshot = UsageMetricsSnapshot()
            status = .resetAfterInvalidData
        }
    }

    func recordStarted(audioSeconds: Double) throws -> UsageMetricsSnapshot {
        var updated = snapshot
        updated.recordStarted(audioSeconds: audioSeconds)
        return try persist(updated)
    }

    func recordCompletion(_ event: DictationMetricEvent) throws -> UsageMetricsSnapshot {
        var updated = snapshot
        updated.recordCompletion(event)
        return try persist(updated)
    }

    private func persist(_ updated: UsageMetricsSnapshot) throws -> UsageMetricsSnapshot {
        guard let data = try? JSONEncoder().encode(updated) else {
            status = .persistenceFailed
            throw MetricsStoreError.encodingFailed
        }
        defaults.set(data, forKey: Self.defaultsKey)
        snapshot = updated
        status = .available
        return updated
    }
}

@MainActor
final class NoOpUsageMetricsStore: UsageMetricsRecording {
    private(set) var snapshot = UsageMetricsSnapshot()
    let status = MetricsStoreStatus.available

    func recordStarted(audioSeconds: Double) throws -> UsageMetricsSnapshot {
        snapshot.recordStarted(audioSeconds: audioSeconds)
        return snapshot
    }

    func recordCompletion(_ event: DictationMetricEvent) throws -> UsageMetricsSnapshot {
        snapshot.recordCompletion(event)
        return snapshot
    }
}
