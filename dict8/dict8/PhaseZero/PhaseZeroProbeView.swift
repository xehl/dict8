import SwiftUI

struct PhaseZeroProbeView: View {
    @StateObject private var hotkeyProbe = HotkeyProbe()
    @State private var focusedElement: FocusedElementSnapshot?
    @State private var actionMessage = "Probe has not started."

    var body: some View {
        Form {
            Section("Phase 0 validation probe") {
                Text("This temporary harness validates macOS assumptions. It does not record, transcribe, clean, or paste.")
                LabeledContent("Accessibility") {
                    Text(hotkeyProbe.accessibilityIsTrusted ? "Granted" : "Not granted")
                }
                LabeledContent("Event tap") {
                    Text(hotkeyProbe.isRunning ? "Running" : "Stopped")
                }
                LabeledContent("Control + Option presses") {
                    Text(hotkeyProbe.pressCount, format: .number)
                }
                LabeledContent("Releases") {
                    Text(hotkeyProbe.releaseCount, format: .number)
                }
            }

            Section("Captured target") {
                LabeledContent("Bundle ID") {
                    Text(focusedElement?.bundleIdentifier ?? "—")
                }
                LabeledContent("Role") {
                    Text(focusedElement?.role ?? "—")
                }
                LabeledContent("Subrole") {
                    Text(focusedElement?.subrole ?? "—")
                }
                LabeledContent("Secure field") {
                    Text(focusedElement?.isSecureTextField == true ? "Yes" : "No")
                }
                Text(focusedElement?.diagnostic ?? "Hold Control + Option while another app is focused.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Request Accessibility") {
                        hotkeyProbe.requestAccessibilityPermission()
                    }
                    Button(hotkeyProbe.isRunning ? "Stop Probe" : "Start Probe") {
                        toggleProbe()
                    }
                }
                Text(actionMessage)
                    .foregroundStyle(.secondary)
                if let lastError = hotkeyProbe.lastError {
                    Text(lastError)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 440)
        .onAppear {
            hotkeyProbe.onPress = {
                focusedElement = FocusedElementProbe.capture()
            }
        }
        .onDisappear {
            hotkeyProbe.stop()
        }
    }

    private func toggleProbe() {
        if hotkeyProbe.isRunning {
            hotkeyProbe.stop()
            actionMessage = "Probe stopped."
            return
        }

        do {
            try hotkeyProbe.start()
            actionMessage = "Focus TextEdit or a browser field, then hold and release Control + Option."
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}
