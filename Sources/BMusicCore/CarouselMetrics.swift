import Foundation

public struct CarouselMetrics: Sendable {
    public static let inset: Double = 28
    public static let spacing: Double = 18
    public let cardWidth: Double
    public let coverHeight: Double
    public let pageSize: Int
    public var arrowCenterY: Double { coverHeight / 2 }

    public init(viewport: Double, featured: Bool) {
        let available = max(1, viewport - Self.inset * 2)
        let preferred: Double = featured ? 260 : 180
        let columns = max(1, Int((available + Self.spacing) / (preferred + Self.spacing)))
        let fitting = (available - Double(columns - 1) * Self.spacing) / Double(columns)
        cardWidth = min(available, min(featured ? 290 : 200, fitting))
        coverHeight = cardWidth * (featured ? 1.33 : 1)
        pageSize = max(1, Int((available + Self.spacing) / (cardWidth + Self.spacing)))
    }
}
