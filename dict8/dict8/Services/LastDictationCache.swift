import AppKit
import Foundation

@MainActor
protocol LastDictationCaching: AnyObject {
    func store(_ text: String)
    func value() -> String?
    func clear()
}

@MainActor
final class LastDictationCache: LastDictationCaching {
    static let v0Lifetime: TimeInterval = 10 * 60
    static let v0PrivacyNotifications: [Notification.Name] = [
        NSWorkspace.sessionDidResignActiveNotification,
        NSWorkspace.screensDidSleepNotification,
        NSWorkspace.willSleepNotification,
    ]

    private struct Entry {
        let text: String
        let expiresAt: Date
    }

    private let lifetime: TimeInterval
    private let now: () -> Date
    private let notificationCenter: NotificationCenter
    private var entry: Entry?
    private var expirationTask: Task<Void, Never>?
    private var privacyObservers: [NSObjectProtocol] = []

    init(
        lifetime: TimeInterval = LastDictationCache.v0Lifetime,
        now: @escaping () -> Date = Date.init,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        privacyNotifications: [Notification.Name] = LastDictationCache.v0PrivacyNotifications
    ) {
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

    func store(_ text: String) {
        expirationTask?.cancel()
        entry = Entry(text: text, expiresAt: now().addingTimeInterval(lifetime))
        let lifetime = lifetime

        expirationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(lifetime))
            } catch {
                return
            }
            self?.discardIfExpired()
        }
    }

    func value() -> String? {
        discardIfExpired()
        return entry?.text
    }

    func clear() {
        expirationTask?.cancel()
        expirationTask = nil
        entry = nil
    }

    private func discardIfExpired() {
        guard let entry, entry.expiresAt <= now() else { return }
        clear()
    }
}
