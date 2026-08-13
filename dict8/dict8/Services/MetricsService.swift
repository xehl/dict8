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

/// Content-free classification of why a cleanup attempt fell back to the raw
/// transcript. Carries no transcript, prompt, or response content — only the
/// structural failure class, so it is safe to persist and aggregate in
/// `UsageMetricsSnapshot` per AGENTS.md §21.
nonisolated enum CleanupFailureReason: String, Codable, Equatable, Sendable, CaseIterable {
    case invalidInput
    case requestEncodingFailed
    case invalidResponse
    case incompleteOutput
    case emptyOutput
    case suspiciousMarkdownFence
    case suspiciousCommentaryWrapper
    case suspiciousSubstantialExpansion
    case suspiciousExcessiveNovelContent
    case suspiciousInsufficientSourceRetention
    case transportDeadlineExceeded
    case transportNetworkFailure
    case transportRateLimited
    case transportServerFailure
    case transportAuthentication
    case transportOther

    var displayName: String {
        switch self {
        case .invalidInput: "Invalid input"
        case .requestEncodingFailed: "Request encoding failed"
        case .invalidResponse: "Invalid response"
        case .incompleteOutput: "Incomplete output"
        case .emptyOutput: "Empty output"
        case .suspiciousMarkdownFence: "Rejected: Markdown fence"
        case .suspiciousCommentaryWrapper: "Rejected: commentary wrapper"
        case .suspiciousSubstantialExpansion: "Rejected: substantial expansion"
        case .suspiciousExcessiveNovelContent: "Rejected: excessive novel content"
        case .suspiciousInsufficientSourceRetention: "Rejected: insufficient source retention"
        case .transportDeadlineExceeded: "Timed out"
        case .transportNetworkFailure: "Network failure"
        case .transportRateLimited: "Rate limited"
        case .transportServerFailure: "Server failure"
        case .transportAuthentication: "Authentication failure"
        case .transportOther: "Other transport failure"
        }
    }

    /// Whether this reason indicates the deadline was the cause, as opposed
    /// to a rejected-but-timely response or a non-timeout transport error.
    var isLatencyRelated: Bool {
        self == .transportDeadlineExceeded
    }

    init(cleanupError: TextCleanupError) {
        switch cleanupError {
        case .invalidInput: self = .invalidInput
        case .requestEncodingFailed: self = .requestEncodingFailed
        case .invalidResponse: self = .invalidResponse
        case .incompleteOutput: self = .incompleteOutput
        case .emptyOutput: self = .emptyOutput
        case let .suspiciousOutput(reason):
            switch reason {
            case .markdownFence: self = .suspiciousMarkdownFence
            case .commentaryWrapper: self = .suspiciousCommentaryWrapper
            case .substantialExpansion: self = .suspiciousSubstantialExpansion
            case .excessiveNovelContent: self = .suspiciousExcessiveNovelContent
            case .insufficientSourceRetention: self = .suspiciousInsufficientSourceRetention
            }
        case let .transport(transportError):
            switch transportError {
            case .deadlineExceeded: self = .transportDeadlineExceeded
            case .networkFailure, .cancelled: self = .transportNetworkFailure
            case .rateLimited: self = .transportRateLimited
            case .serverFailure, .providerUnavailable, .zdrUnavailable: self = .transportServerFailure
            case .authentication, .missingAPIKey, .credentialUnavailable, .forbidden:
                self = .transportAuthentication
            default: self = .transportOther
            }
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
    let cleanupFailureReason: CleanupFailureReason?
}

nonisolated struct UsageMetricsSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    /// Bound on how many recent per-request latency samples are retained per
    /// stage for percentile estimation. Content-free (durations only, no
    /// transcript/audio data) but kept bounded — per AGENTS.md §21, metrics
    /// must stay aggregate rather than an unbounded content-free log.
    static let latencySampleCap = 200

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
    var cleanupFallbackReasonCounts: [String: Int] = [:]
    /// Most recent transcription/cleanup/end-to-end latency samples
    /// (seconds), each capped at `latencySampleCap`, used only to estimate
    /// p50/p95. Oldest samples are dropped once the cap is reached.
    var transcriptionLatencySamples: [Double] = []
    var cleanupLatencySamples: [Double] = []
    var pipelineLatencySamples: [Double] = []

    var cancellationCount: Int {
        max(0, requestCount - successCount - failureCount)
    }

    var audioMinutes: Double {
        totalAudioSeconds / 60
    }

    var totalReportedCost: Double {
        totalTranscriptionCost + totalCleanupCost
    }

    /// Fraction of completed requests (success + failure) that succeeded.
    /// Nil when no request has completed yet, so callers can distinguish
    /// "no data" from "0% success."
    var successRate: Double? {
        let completed = successCount + failureCount
        guard completed > 0 else { return nil }
        return Double(successCount) / Double(completed)
    }

    /// Reported cost divided across successful requests. Nil when there are
    /// no successful requests yet, since cost is only meaningful per
    /// completed dictation.
    var averageCostPerRequest: Double? {
        guard successCount > 0 else { return nil }
        return totalReportedCost / Double(successCount)
    }

    /// Reported cost divided across recorded audio minutes. Nil until some
    /// audio has been recorded, since cost-per-minute is undefined for a
    /// zero denominator.
    var costPerAudioMinute: Double? {
        guard audioMinutes > 0 else { return nil }
        return totalReportedCost / audioMinutes
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

    var p50TranscriptionLatencySeconds: Double? {
        Self.percentile(transcriptionLatencySamples, 0.5)
    }

    var p95TranscriptionLatencySeconds: Double? {
        Self.percentile(transcriptionLatencySamples, 0.95)
    }

    var p50CleanupLatencySeconds: Double? {
        Self.percentile(cleanupLatencySamples, 0.5)
    }

    var p95CleanupLatencySeconds: Double? {
        Self.percentile(cleanupLatencySamples, 0.95)
    }

    var p50PipelineLatencySeconds: Double? {
        Self.percentile(pipelineLatencySamples, 0.5)
    }

    var p95PipelineLatencySeconds: Double? {
        Self.percentile(pipelineLatencySamples, 0.95)
    }

    /// The most frequent recorded cleanup fallback reason, if any fallbacks
    /// have been recorded. Content-free: only the structural reason and its
    /// count, never transcript or response content.
    var topCleanupFallbackReason: (reason: CleanupFailureReason, count: Int)? {
        cleanupFallbackReasonCounts
            .compactMap { key, count in CleanupFailureReason(rawValue: key).map { ($0, count) } }
            .max { $0.1 < $1.1 }
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
            Self.appendSample(seconds, to: &transcriptionLatencySamples)
        }
        if let seconds = Self.validSeconds(event.cleanupLatency) {
            totalCleanupLatencySeconds += seconds
            cleanupLatencyCount += 1
            Self.appendSample(seconds, to: &cleanupLatencySamples)
        }
        if let seconds = Self.validSeconds(event.totalLatency) {
            totalPipelineLatencySeconds += seconds
            pipelineLatencyCount += 1
            Self.appendSample(seconds, to: &pipelineLatencySamples)
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
        if let reason = event.cleanupFailureReason {
            cleanupFallbackReasonCounts[reason.rawValue, default: 0] += 1
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
            && cleanupFallbackReasonCounts.values.allSatisfy { $0 >= 0 }
            && transcriptionLatencySamples.count <= Self.latencySampleCap
            && cleanupLatencySamples.count <= Self.latencySampleCap
            && pipelineLatencySamples.count <= Self.latencySampleCap
            && transcriptionLatencySamples.allSatisfy(Self.validNumber)
            && cleanupLatencySamples.allSatisfy(Self.validNumber)
            && pipelineLatencySamples.allSatisfy(Self.validNumber)
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

    private static func appendSample(_ seconds: Double, to samples: inout [Double]) {
        samples.append(seconds)
        if samples.count > latencySampleCap {
            samples.removeFirst(samples.count - latencySampleCap)
        }
    }

    /// Nearest-rank percentile over the retained sample window. Returns nil
    /// when there are no samples yet.
    private static func percentile(_ samples: [Double], _ fraction: Double) -> Double? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        let index = max(0, min(sorted.count - 1, rank - 1))
        return sorted[index]
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

    // MARK: Codable

    // Custom Codable so that older persisted snapshots without
    // `cleanupFallbackReasonCounts`/latency sample arrays (added after v0's
    // initial release) decode successfully instead of being treated as
    // invalid data and reset. Swift's synthesized `Decodable` does not apply
    // a property's default value to a missing key; it throws `keyNotFound`
    // instead.
    enum CodingKeys: String, CodingKey {
        case version
        case requestCount
        case successCount
        case failureCount
        case totalAudioSeconds
        case totalTranscriptionCost
        case totalCleanupCost
        case totalTranscriptionLatencySeconds
        case transcriptionLatencyCount
        case totalCleanupLatencySeconds
        case cleanupLatencyCount
        case totalPipelineLatencySeconds
        case pipelineLatencyCount
        case cleanupFallbackCount
        case lastIssueCategory
        case cleanupFallbackReasonCounts
        case transcriptionLatencySamples
        case cleanupLatencySamples
        case pipelineLatencySamples
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        requestCount = try container.decode(Int.self, forKey: .requestCount)
        successCount = try container.decode(Int.self, forKey: .successCount)
        failureCount = try container.decode(Int.self, forKey: .failureCount)
        totalAudioSeconds = try container.decode(Double.self, forKey: .totalAudioSeconds)
        totalTranscriptionCost = try container.decode(Double.self, forKey: .totalTranscriptionCost)
        totalCleanupCost = try container.decode(Double.self, forKey: .totalCleanupCost)
        totalTranscriptionLatencySeconds = try container.decode(
            Double.self,
            forKey: .totalTranscriptionLatencySeconds
        )
        transcriptionLatencyCount = try container.decode(Int.self, forKey: .transcriptionLatencyCount)
        totalCleanupLatencySeconds = try container.decode(Double.self, forKey: .totalCleanupLatencySeconds)
        cleanupLatencyCount = try container.decode(Int.self, forKey: .cleanupLatencyCount)
        totalPipelineLatencySeconds = try container.decode(Double.self, forKey: .totalPipelineLatencySeconds)
        pipelineLatencyCount = try container.decode(Int.self, forKey: .pipelineLatencyCount)
        cleanupFallbackCount = try container.decode(Int.self, forKey: .cleanupFallbackCount)
        lastIssueCategory = try container.decodeIfPresent(
            DictationIssueCategory.self,
            forKey: .lastIssueCategory
        )
        cleanupFallbackReasonCounts = try container.decodeIfPresent(
            [String: Int].self,
            forKey: .cleanupFallbackReasonCounts
        ) ?? [:]
        transcriptionLatencySamples = try container.decodeIfPresent(
            [Double].self,
            forKey: .transcriptionLatencySamples
        ) ?? []
        cleanupLatencySamples = try container.decodeIfPresent(
            [Double].self,
            forKey: .cleanupLatencySamples
        ) ?? []
        pipelineLatencySamples = try container.decodeIfPresent(
            [Double].self,
            forKey: .pipelineLatencySamples
        ) ?? []
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
