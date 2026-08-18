import AppKit
import Foundation

nonisolated struct CleanupDiagnosticEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let model: String
    let input: String
    let candidateOutput: String
    let failure: CleanupValidationFailure
    let inputWordCount: Int
    let outputWordCount: Int
    let novelWordCount: Int
    let novelWordRatio: Double
    let expansionRatio: Double
    let expiresAt: Date

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        model: String,
        input: String,
        candidateOutput: String,
        failure: CleanupValidationFailure,
        inputWordCount: Int,
        outputWordCount: Int,
        novelWordCount: Int,
        novelWordRatio: Double,
        expansionRatio: Double,
        expiresAt: Date
    ) {
        self.id = id
        self.timestamp = timestamp
        self.model = model
        self.input = input
        self.candidateOutput = candidateOutput
        self.failure = failure
        self.inputWordCount = inputWordCount
        self.outputWordCount = outputWordCount
        self.novelWordCount = novelWordCount
        self.novelWordRatio = novelWordRatio
        self.expansionRatio = expansionRatio
        self.expiresAt = expiresAt
    }
}

@MainActor
protocol CleanupDiagnosticLogging: AnyObject {
    func record(
        model: String,
        input: String,
        candidateOutput: String,
        failure: CleanupValidationFailure,
        inputWordCount: Int,
        outputWordCount: Int,
        novelWordCount: Int,
        novelWordRatio: Double,
        expansionRatio: Double
    )
    func entries() -> [CleanupDiagnosticEntry]
    func clear()
}

@MainActor
final class NoOpCleanupDiagnosticStore: CleanupDiagnosticLogging {
    func record(
        model: String,
        input: String,
        candidateOutput: String,
        failure: CleanupValidationFailure,
        inputWordCount: Int,
        outputWordCount: Int,
        novelWordCount: Int,
        novelWordRatio: Double,
        expansionRatio: Double
    ) {}

    func entries() -> [CleanupDiagnosticEntry] {
        []
    }

    func clear() {}
}

@MainActor
final class CleanupDiagnosticStore: CleanupDiagnosticLogging {
    static let maxEntries = 20
    static let defaultLifetime: TimeInterval = 10 * 60

    private let capacity: Int
    private let lifetime: TimeInterval
    private let now: () -> Date
    private let notificationCenter: NotificationCenter
    private var buffer: [CleanupDiagnosticEntry] = []
    private var privacyObservers: [NSObjectProtocol] = []

    init(
        capacity: Int = CleanupDiagnosticStore.maxEntries,
        lifetime: TimeInterval = CleanupDiagnosticStore.defaultLifetime,
        now: @escaping () -> Date = Date.init,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        privacyNotifications: [Notification.Name] = LastDictationCache.v0PrivacyNotifications
    ) {
        self.capacity = capacity
        self.lifetime = lifetime
        self.now = now
        self.notificationCenter = notificationCenter

        privacyObservers = privacyNotifications.map { notificationName in
            notificationCenter.addObserver(
                forName: notificationName,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.clear()
                }
            }
        }
    }

    func record(
        model: String,
        input: String,
        candidateOutput: String,
        failure: CleanupValidationFailure,
        inputWordCount: Int,
        outputWordCount: Int,
        novelWordCount: Int,
        novelWordRatio: Double,
        expansionRatio: Double
    ) {
        pruneExpired()
        let entry = CleanupDiagnosticEntry(
            timestamp: now(),
            model: model,
            input: input,
            candidateOutput: candidateOutput,
            failure: failure,
            inputWordCount: inputWordCount,
            outputWordCount: outputWordCount,
            novelWordCount: novelWordCount,
            novelWordRatio: novelWordRatio,
            expansionRatio: expansionRatio,
            expiresAt: now().addingTimeInterval(lifetime)
        )
        buffer.append(entry)
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
    }

    func entries() -> [CleanupDiagnosticEntry] {
        pruneExpired()
        return buffer
    }

    func clear() {
        buffer.removeAll()
    }

    private func pruneExpired() {
        let current = now()
        buffer.removeAll { $0.expiresAt <= current }
    }
}
