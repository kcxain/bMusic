import SwiftUI

/// Keep transport centred; metadata yields width before controls do.
struct PlayerControlsLayout: Layout {
    private let gap: CGFloat = 10
    private func measurements(_ subviews: Subviews) -> [CGSize] {
        subviews.map { $0.sizeThatFits(.unspecified) }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = measurements(subviews)
        return CGSize(width: proposal.width ?? 724, height: sizes.map(\.height).max() ?? 40)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = measurements(subviews)
        guard sizes.count == 3 else { return }
        let controls = sizes[1].width
        // At supported window widths the controls fit around the exact centre.
        // For unusually narrow proposals, keep the right-hand controls in bounds.
        let centre = max(bounds.minX + controls / 2,
                         min(bounds.midX, bounds.maxX - sizes[2].width - gap - controls / 2))
        let metadataWidth = max(0, centre - controls / 2 - gap - bounds.minX)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: metadataWidth, height: bounds.height))
        subviews[1].place(at: CGPoint(x: centre, y: bounds.midY), anchor: .center, proposal: .unspecified)
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: .unspecified)
    }
}
