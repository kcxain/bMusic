import SwiftUI

/// Shared icon control: geometry, accessibility and interaction stay in one place.
struct MusicIconButton: View {
    let symbol: String
    let label: String
    var color: Color = .primary
    var size: CGFloat = 17
    var width: CGFloat = 32
    var height: CGFloat = 36
    var prominent = false
    var loading = false
    var hoverEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if loading { ProgressView().controlSize(.small) }
                else { Image(systemName: symbol).font(.system(size: size, weight: .medium)) }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(MusicIconStyle(color: color, prominent: prominent, hoverEnabled: hoverEnabled))
        .help(label).accessibilityLabel(label)
    }
}

private struct MusicIconStyle: ButtonStyle {
    let color: Color
    let prominent: Bool
    let hoverEnabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(IconHoverFeedback(color: color, pressed: configuration.isPressed, prominent: prominent, hoverEnabled: hoverEnabled))
    }
}
