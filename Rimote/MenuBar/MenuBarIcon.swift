import SwiftUI

/// The three-state menubar icon (PRD §11):
///  - connected: filled circle, green tint,
///  - idle: outline circle, neutral,
///  - error: warning triangle.
///
/// SF Symbols are template images, so they tint correctly for light/dark menubars;
/// the connected state's green is the one deliberate splash of color.
/// Observes `AppState` so the menubar label re-renders as the icon state changes.
struct MenuBarLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        MenuBarIcon(state: state.iconState)
    }
}

struct MenuBarIcon: View {

    let state: AppState.IconState

    var body: some View {
        Image(systemName: symbolName)
            .renderingMode(state == .connected ? .original : .template)
            .foregroundStyle(tint)
    }

    private var symbolName: String {
        switch state {
        case .connected: return "circle.fill"
        case .idle: return "circle"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .connected: return .green
        case .idle: return .primary
        case .error: return .orange
        }
    }
}
