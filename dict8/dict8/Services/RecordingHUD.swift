import AppKit
import SwiftUI

enum TransientFeedback: Equatable, Sendable {
    case copiedBecauseFocusChanged
    case pasteLastUnavailable
    case pasteLastSucceeded

    var symbolName: String {
        switch self {
        case .copiedBecauseFocusChanged: "doc.on.clipboard"
        case .pasteLastUnavailable: "clock.badge.exclamationmark"
        case .pasteLastSucceeded: "checkmark.circle"
        }
    }

    var message: String {
        switch self {
        case .copiedBecauseFocusChanged: "Copied — focus changed"
        case .pasteLastUnavailable: "No recent dictation"
        case .pasteLastSucceeded: "Pasted last dictation"
        }
    }
}

@MainActor
protocol RecordingHUDPresenting: AnyObject {
    func showPreview(for duration: Duration)
    func showFeedback(_ feedback: TransientFeedback)
    func hide()
}

@MainActor
final class RecordingHUDController: RecordingHUDPresenting {
    private let panel: NSPanel
    private var presentationTask: Task<Void, Never>?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 72, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: TransientHUDView(symbolName: "mic.fill", message: nil)
        )
    }

    deinit {
        presentationTask?.cancel()
    }

    func showPreview(for duration: Duration) {
        present(
            symbolName: "mic.fill",
            message: nil,
            width: 72,
            duration: duration
        )
    }

    func showFeedback(_ feedback: TransientFeedback) {
        present(
            symbolName: feedback.symbolName,
            message: feedback.message,
            width: 244,
            duration: .seconds(2)
        )
    }

    func hide() {
        presentationTask?.cancel()
        presentationTask = nil
        panel.orderOut(nil)
    }

    private func present(
        symbolName: String,
        message: String?,
        width: CGFloat,
        duration: Duration
    ) {
        presentationTask?.cancel()
        panel.setContentSize(NSSize(width: width, height: 48))
        panel.contentView = NSHostingView(
            rootView: TransientHUDView(symbolName: symbolName, message: message)
        )
        positionOnActiveScreen()
        panel.orderFrontRegardless()

        presentationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func positionOnActiveScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let panelFrame = panel.frame
        let origin = NSPoint(
            x: visibleFrame.midX - panelFrame.width / 2,
            y: visibleFrame.minY + 28
        )
        panel.setFrameOrigin(origin)
    }
}

private struct TransientHUDView: View {
    let symbolName: String
    let message: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 20, weight: .semibold))

            if let message {
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(.black.opacity(0.78), in: Capsule())
        .accessibilityLabel(message ?? "Recording")
    }
}
