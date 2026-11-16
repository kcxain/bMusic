import Testing
@testable import BMusicCore

struct CarouselMetricsTests {
    @Test func resizingKeepsCardsWithinViewportAndArrowsOnArtworkCentre() {
        // Includes detail widths with collapsed/expanded sidebar and external displays.
        for viewport in stride(from: 320.0, through: 5120.0, by: 13) {
            for featured in [false, true] {
                let metrics = CarouselMetrics(viewport: viewport, featured: featured)
                let available = viewport - CarouselMetrics.inset * 2
                #expect(metrics.cardWidth > 0)
                #expect(metrics.cardWidth <= available)
                #expect(metrics.cardWidth <= (featured ? 290 : 200))
                #expect(metrics.pageSize >= 1)
                let occupied = Double(metrics.pageSize) * metrics.cardWidth + Double(metrics.pageSize - 1) * CarouselMetrics.spacing
                #expect(occupied <= available + 0.001)
                #expect(metrics.arrowCenterY == metrics.coverHeight / 2)
                #expect(metrics.coverHeight == metrics.cardWidth * (featured ? 1.33 : 1))
            }
        }
    }
}
