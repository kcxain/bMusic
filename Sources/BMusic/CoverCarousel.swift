import SwiftUI
import BMusicCore

/// Native scroll position tracks both trackpad gestures and arrow navigation.
struct CoverCarousel<Card: View>: View {
    let tracks: [Track]
    let cardWidth: CGFloat
    let coverHeight: CGFloat
    let viewportWidth: CGFloat
    @ViewBuilder let card: (Int, Track) -> Card
    @ViewState<String?> private var leadingTrackID = nil
    @ViewState<Bool> private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var pageSize: Int {
        max(1, Int((viewportWidth - CarouselMetrics.inset * 2 + CarouselMetrics.spacing) / (cardWidth + CarouselMetrics.spacing)))
    }
    private var index: Int { tracks.firstIndex { $0.id == leadingTrackID } ?? 0 }
    private var lastPageIndex: Int { max(0, tracks.count - pageSize) }
    private var canGoBack: Bool { index > 0 }
    private var canGoForward: Bool { index < lastPageIndex }
    var body: some View {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: CarouselMetrics.spacing) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        card(index, track).id(track.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.bottom, 8)
            }
            .contentMargins(.horizontal, CarouselMetrics.inset, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $leadingTrackID, anchor: .leading)
            .overlay(alignment: .topLeading) {
                arrow("chevron.left", label: "上一页", enabled: canGoBack) { turn(-1) }
                    .frame(height: coverHeight)
            }
            .overlay(alignment: .topTrailing) {
                arrow("chevron.right", label: "下一页", enabled: canGoForward) { turn(1) }
                    .frame(height: coverHeight)
            }
            .onHover { hovering = $0 }
            .onChange(of: tracks.map(\.id)) {
                if !tracks.contains(where: { $0.id == leadingTrackID }) { leadingTrackID = tracks.first?.id }
            }
    }
    private func turn(_ direction: Int) {
        guard !tracks.isEmpty else { return }
        let target = min(max(0, index + direction * pageSize), lastPageIndex)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            leadingTrackID = tracks[target].id
        }
    }
    private func arrow(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))

                .frame(width: 28, height: 52)
                .iconHoverFeedback(color: enabled ? .primary : .secondary.opacity(0.4))
                .musicGlass(cornerRadius: 10, interactive: true)
        }
        .buttonStyle(.plain).padding(.horizontal, 6)
        .disabled(!enabled)
        .opacity(hovering ? 1 : 0)
        .allowsHitTesting(hovering)
        .accessibilityLabel(label)
        .help(enabled ? label : (symbol == "chevron.left" ? "已到开头" : "已到末尾"))
    }
}
