import SwiftUI

/// The menubar popover (PRD §11): a status line, the pairing PIN (only while a
/// pairing attempt is active), a Launch-at-Login toggle, Forget Paired Device,
/// and Quit.
struct MenuBarView: View {

    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow

            if let pin = state.activePIN {
                Divider()
                pinRow(pin)
            }

            Divider()

            Toggle("Launch at Login", isOn: launchAtLoginBinding)
                .toggleStyle(.checkbox)

            Button("Forget Paired Device", action: state.forgetPairedDevice)
                .disabled(!state.isPaired)

            Divider()

            Button("Quit Rimote") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 240)
    }

    // MARK: - Rows

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(state.statusText)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pinRow(_ pin: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Pairing PIN")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(pin)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .tracking(4)
            Text("Enter this on your iPhone within 60 seconds.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { state.launchAtLogin },
            set: { state.setLaunchAtLogin($0) }
        )
    }

    private var statusColor: Color {
        switch state.iconState {
        case .connected: return .green
        case .idle: return .secondary
        case .error: return .orange
        }
    }
}
