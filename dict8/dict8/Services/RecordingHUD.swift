import AppKit
import SwiftUI

enum TransientFeedback: Equatable, Sendable {
    case copiedBecauseFocusChanged
    case pasteLastUnavailable
    case pasteLastSucceeded
    case recordingLimitReached
    case secureFieldRefused
    case recordingCueFailed
    case transcriptionFallbackUsed
    case cleanupRawFallback
    case temporaryAudioCleanupFailed

    var symbolName: String {
        switch self {
        case .copiedBecauseFocusChanged: "doc.on.clipboard"
        case .pasteLastUnavailable: "clock.badge.exclamationmark"
        case .pasteLastSucceeded: "checkmark.circle"
        case .recordingLimitReached: "timer"
        case .secureFieldRefused: "lock.fill"
        case .recordingCueFailed: "speaker.slash"
        case .transcriptionFallbackUsed: "arrow.trianglehead.2.clockwise.rotate.90"
        case .cleanupRawFallback: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .temporaryAudioCleanupFailed: "trash.slash"
        }
    }

    var message: String {
        switch self {
        case .copiedBecauseFocusChanged: "Copied — focus changed"
        case .pasteLastUnavailable: "No recent dictation"
        case .pasteLastSucceeded: "Pasted last dictation"
        case .recordingLimitReached: "3-minute limit reached — recording stopped"
        case .secureFieldRefused: "Recording blocked in secure field"
        case .recordingCueFailed: "Recording cue failed — processing continued"
        case .transcriptionFallbackUsed: "Transcription fallback model used"
        case .cleanupRawFallback: "Cleanup failed — pasted raw transcript"
        case .temporaryAudioCleanupFailed: "Temporary audio could not be deleted"
        }
    }
}

@MainActor
protocol RecordingHUDPresenting: AnyObject {
    func showPreview(for duration: Duration)
    func showRecording()
    func showProcessing()
    func showFeedback(_ feedback: TransientFeedback)
    func finishProcessing()
    func hide()
}

extension RecordingHUDPresenting {
    func showProcessing() {}
    func finishProcessing() { hide() }
}

@MainActor
final class RecordingHUDController: RecordingHUDPresenting {
    private enum PersistentPresentation: Equatable {
        case recording
        case processing
    }

    private let panel: NSPanel
    private let hostingView: NSHostingView<TransientHUDView>
    private var presentationTask: Task<Void, Never>?
    private var persistentPresentation: PersistentPresentation?
    private var isShowingTransient = false

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
        hostingView = NSHostingView(
            rootView: TransientHUDView(symbolName: "mic.fill", message: nil)
        )
        panel.contentView = hostingView
    }

    deinit {
        presentationTask?.cancel()
    }

    func showPreview(for duration: Duration) {
        persistentPresentation = nil
        showTransient(
            symbolName: "mic.fill",
            message: nil,
            width: 72,
            duration: duration
        )
    }

    func showRecording() {
        presentationTask?.cancel()
        presentationTask = nil
        persistentPresentation = .recording
        isShowingTransient = false
        present(
            symbolName: "mic.fill",
            message: nil,
            width: 72
        )
    }

    func showProcessing() {
        presentationTask?.cancel()
        presentationTask = nil
        persistentPresentation = .processing
        isShowingTransient = false
        present(
            symbolName: nil,
            message: nil,
            width: 72
        )
    }

    func showFeedback(_ feedback: TransientFeedback) {
        showTransient(
            symbolName: feedback.symbolName,
            message: feedback.message,
            width: 244,
            duration: .seconds(2)
        )
    }

    func finishProcessing() {
        guard persistentPresentation == .processing else { return }
        persistentPresentation = nil
        if !isShowingTransient {
            panel.orderOut(nil)
        }
    }

    func hide() {
        presentationTask?.cancel()
        presentationTask = nil
        persistentPresentation = nil
        isShowingTransient = false
        panel.orderOut(nil)
    }

    private func showTransient(
        symbolName: String?,
        message: String?,
        width: CGFloat,
        duration: Duration
    ) {
        presentationTask?.cancel()
        isShowingTransient = true
        present(symbolName: symbolName, message: message, width: width)
        presentationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.isShowingTransient = false
            self.presentationTask = nil
            self.restorePersistentPresentation()
        }
    }

    private func present(
        symbolName: String?,
        message: String?,
        width: CGFloat
    ) {
        hostingView.rootView = TransientHUDView(symbolName: symbolName, message: message)
        panel.setContentSize(NSSize(width: width, height: 48))
        positionOnActiveScreen()
        panel.orderFrontRegardless()
    }

    private func restorePersistentPresentation() {
        switch persistentPresentation {
        case .recording:
            present(symbolName: "mic.fill", message: nil, width: 72)
        case .processing:
            present(symbolName: nil, message: nil, width: 72)
        case nil:
            panel.orderOut(nil)
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
    let symbolName: String?
    let message: String?

    var body: some View {
        HStack(spacing: 10) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 20, weight: .semibold))
            } else {
                ProcessingSpinner()
            }

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
        .accessibilityLabel(message ?? (symbolName == nil ? "Processing dictation" : "Recording"))
    }
}

private struct ProcessingSpinner: View {
    @State private var isRotating = false

    var body: some View {
        Circle()
            .trim(from: 0.14, to: 0.86)
            .stroke(
                .white,
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
            .frame(width: 18, height: 18)
            .rotationEffect(.degrees(isRotating ? 360 : 0))
            .onAppear {
                withAnimation(
                    .linear(duration: 0.8)
                        .repeatForever(autoreverses: false)
                ) {
                    isRotating = true
                }
            }
    }
}
