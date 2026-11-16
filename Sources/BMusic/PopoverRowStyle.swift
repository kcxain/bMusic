import SwiftUI

/// Shared tint feedback without adding a background or changing the hit target.
private struct IconHoverFeedback: ViewModifier {
    let color: Color
    @ViewState private var hovering = false
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View {
        content.foregroundStyle(enabled && hovering ? BMusicTheme.pink : color)
            .onHover { hovering = $0 }
    }
}

extension View {
    func iconHoverFeedback(color: Color = .primary) -> some View {
        modifier(IconHoverFeedback(color: color))
    }
}

/// Icon controls retain their hit area and use a light press response.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Consistent feedback for the compact native popover lists.
struct PopoverRowStyle: ButtonStyle {
    var selected = false
    var hoverEnabled = true
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, selected: selected, hoverEnabled: hoverEnabled)
    }
    private struct Row: View {
        let configuration: ButtonStyle.Configuration
        let selected: Bool
        let hoverEnabled: Bool
        @ViewState private var hovering = false
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(enabled && configuration.isPressed ? 0.14 : (enabled && hoverEnabled && hovering ? 0.09 : (selected ? 0.045 : 0))))
                }
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onHover { hovering = $0 }
        }
    }
}
