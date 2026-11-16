import SwiftUI
import BMusicCore

struct CachedArtwork: View {
    let url: URL?
    var pixels: Int = 400
    @ViewState<NSImage?> private var image = nil
    private struct Request: Equatable { let url: URL?; let pixels: Int }
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { ArtworkPlaceholder() }
        }.task(id: Request(url: url, pixels: pixels)) {
            guard let url else { image = nil; return }
            image = ArtworkService.shared.loaded.image(for: url)
            do {
                let loaded = try await ArtworkService.shared.image(url, pixels: pixels)
                try Task.checkCancellation()
                image = loaded
            } catch { }
        }.onDisappear { image = nil }
    }
}
