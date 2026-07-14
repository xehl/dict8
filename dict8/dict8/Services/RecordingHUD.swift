import AppKit
import SwiftUI

@MainActor
protocol RecordingHUDPresenting: AnyObject {
    func showPreview(for duration: Duration)
    func hide()
}

@MainActor
final class RecordingHUDController: RecordingHUDPresenting {
    private let panel: NSPanel
    private var previewTask: Task<Void, Never>?

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
        panel.contentView = NSHostingView(rootView: RecordingHUDView())
    }

    deinit {
        previewTask?.cancel()
    }

    func showPreview(for duration: Duration) {
        previewTask?.cancel()
        positionOnActiveScreen()
        panel.orderFrontRegardless()

        previewTask = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        previewTask?.cancel()
        previewTask = nil
        panel.orderOut(nil)
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

private struct RecordingHUDView: View {
    var body: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 72, height: 48)
            .background(.black.opacity(0.78), in: Capsule())
            .accessibilityLabel("Recording")
    }
}
