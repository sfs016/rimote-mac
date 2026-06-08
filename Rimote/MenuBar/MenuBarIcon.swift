import AppKit

/// Builds the menu-bar status icon for each connection state (PRD §11):
///  - connected: filled green dot — the one deliberate splash of colour,
///  - idle: neutral outline (template, so it adapts to the menu bar appearance),
///  - error: orange warning triangle.
enum StatusIcon {
    static func image(for state: AppState.IconState) -> NSImage? {
        let symbol: String
        switch state {
        case .connected: symbol = "circle.fill"
        case .idle:      symbol = "circle"
        case .error:     symbol = "exclamationmark.triangle.fill"
        }

        let base = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let configuration: NSImage.SymbolConfiguration
        switch state {
        case .connected: configuration = base.applying(.init(paletteColors: [.systemGreen]))
        case .error:     configuration = base.applying(.init(paletteColors: [.systemOrange]))
        case .idle:      configuration = base
        }

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Rimote")?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = (state == .idle)
        return image
    }
}
