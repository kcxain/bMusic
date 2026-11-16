import SwiftUI

/// Measure controls at their intrinsic sizes. Preserve centred transport at every width.
struct PlayerControlsLayout: Layout {
    private let gap: CGFloat = 12
    private func measurements(_ subviews: Subviews) -> [CGSize] {
        subviews.map { $0.sizeThatFits(.unspecified) }
    }
    private func fits(_ width: CGFloat, sizes: [CGSize]) -> Bool {
        // Metadata can truncate; accessories keep their intrinsic control widths.
        width >= sizes[1].width + 2 * (max(150, sizes[2].width) + gap)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = measurements(subviews)
        guard sizes.count == 3 else { return .zero }
        let width = proposal.width ?? 724
        if fits(width, sizes: sizes) {
            return CGSize(width: width, height: sizes.map(\.height).max() ?? 40)
        }
        return CGSize(width: width, height: max(sizes[0].height, sizes[2].height) + gap + sizes[1].height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = measurements(subviews)
        guard sizes.count == 3 else { return }
        if fits(bounds.width, sizes: sizes) {
            let side = (bounds.width - sizes[1].width) / 2 - gap
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                              proposal: ProposedViewSize(width: side, height: bounds.height))
            subviews[1].place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: .unspecified)
            subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: .unspecified)
        } else {
            let topHeight = max(sizes[0].height, sizes[2].height)
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY + topHeight / 2), anchor: .leading,
                              proposal: ProposedViewSize(width: max(0, bounds.width - sizes[2].width - gap), height: topHeight))
            subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.minY + topHeight / 2), anchor: .trailing, proposal: .unspecified)
            subviews[1].place(at: CGPoint(x: bounds.midX, y: bounds.maxY), anchor: .bottom, proposal: .unspecified)
        }
    }
}
