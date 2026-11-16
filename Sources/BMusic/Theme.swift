import SwiftUI
import AppKit

enum BMusicTheme {
    static let pink = Color(red: 251 / 255, green: 114 / 255, blue: 153 / 255)
    static let blue = Color(red: 0, green: 174 / 255, blue: 236 / 255)
    static let memberGold = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.84, green: 0.72, blue: 0.48, alpha: 1)
            : NSColor(red: 0.48, green: 0.36, blue: 0.17, alpha: 1)
    })
}

extension View {
    @ViewBuilder func musicGlassButton(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) }
            else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) }
            else { self.buttonStyle(.bordered) }
        }
        #else
        if prominent { self.buttonStyle(.borderedProminent) }
        else { self.buttonStyle(.bordered) }
        #endif
    }

    @ViewBuilder func musicGlass(cornerRadius: CGFloat = 22, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            // System glass owns translucency and accessibility appearance.
            self.glassEffect(.regular.interactive(interactive), in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
        #else
        self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        #endif
    }
}

enum BrandAssets {
    // One SVG source supplies the white-backed application icon and generated ICNS.
    static let image: NSImage = {
        let url = Bundle.main.url(forResource: "BMusic", withExtension: "svg")
            ?? Bundle.module.url(forResource: "BMusic", withExtension: "svg")!
        return NSImage(contentsOf: url) ?? NSImage(size: NSSize(width: 32, height: 32))
    }()

}

struct ArtworkPlaceholder: View {
    var body: some View {
        Image(nsImage: BrandAssets.image).resizable().scaledToFit().background(.white)
    }
}

struct AccountAvatar: View {
    let url: URL?
    var isVIP = false
    var body: some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
            ZStack { BMusicTheme.pink.opacity(0.14); Image(systemName: "person.fill").foregroundStyle(BMusicTheme.pink) }
        }.frame(width: 36, height: 36).clipShape(Circle())
            .overlay(Circle().strokeBorder(.primary.opacity(0.06), lineWidth: 0.5))
            .padding(3)
            .overlay {
                if isVIP {
                    Circle().strokeBorder(
                        LinearGradient(colors: [
                            Color(red: 0.64, green: 0.48, blue: 0.26),
                            Color(red: 0.94, green: 0.86, blue: 0.67),
                            Color(red: 0.73, green: 0.58, blue: 0.35),
                            Color(red: 0.88, green: 0.77, blue: 0.54)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5)
                }
            }
            .frame(width: 42, height: 42).clipped()
            .accessibilityLabel("B 站用户头像")
    }
}
