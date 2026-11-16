import SwiftUI

/// Shared layout for native popovers; the system owns material and translucency.
struct MusicPopover<Content: View>: View {
    let title: String
    var clear: (() -> Void)? = nil
    var clearHelp = "清空"
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer(minLength: 8)
                if let clear {
                    Button(action: clear) {
                        Text("清空").padding(.horizontal, 6).padding(.vertical, 4)
                    }.buttonStyle(PopoverRowStyle()).foregroundStyle(.tint).help(clearHelp)
                }
            }
            content()
        }.font(.callout).padding(12)
    }
}

struct PopoverActionLabel: View {
    let title: String
    var symbol: String? = nil
    var selected: Bool? = nil
    var body: some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary) }
            Text(title).lineLimit(1)
            Spacer(minLength: 8)
            if let selected { Image(systemName: "checkmark").frame(width: 16).opacity(selected ? 1 : 0) }
        }.padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 32)
            .contentShape(Rectangle())
    }
}

struct PopoverAction: View {
    let title: String
    var symbol: String? = nil
    var selected: Bool? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) { PopoverActionLabel(title: title, symbol: symbol, selected: selected) }
            .buttonStyle(PopoverRowStyle(selected: selected == true))
    }
}

struct RemoveItemButton: View {
    let help: String
    var rowHovered = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                .frame(width: 26, height: 32).contentShape(Rectangle())
                .iconHoverFeedback(color: rowHovered ? .primary : .secondary)
        }.buttonStyle(IconButtonStyle()).fixedSize()
            .help(help).accessibilityLabel(help)
    }
}

extension View {
    func musicPopover<Content: View>(isPresented: Binding<Bool>, edge: Edge = .top,
                                    @ViewBuilder content: @escaping () -> Content) -> some View {
        popover(isPresented: isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: edge, content: content)
    }
}
