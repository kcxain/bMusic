import SwiftUI
import BMusicCore

/// Drag preview is local and continuous; a single seek is committed on release.
struct SeekBar: View {
    @ObservedObject var timeline: PlaybackTimeline
    let trackID: String?
    let preview: (Double) -> Void
    let commit: (Double) -> Void
    let cancel: () -> Void
    @ViewState<Bool> private var tracking = false
    @ViewState<Double> private var lastX = 0
    @ViewState<Bool> private var hovering = false
    @ViewState<Double?> private var hoverTime = nil
    @ViewState<Double> private var hoverX = 0
    @ViewState<Bool> private var fine = false

    var body: some View {
        HStack(spacing: 10) {
            Text(TextFormatting.time(timeline.elapsed)).frame(width: 56, alignment: .trailing)
            GeometryReader { geometry in
                let width = max(1, geometry.size.width - 12)
                let duration = max(1, timeline.duration)
                let x = min(width, max(0, timeline.elapsed / duration * width))
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.10)).frame(height: 5)
                    ForEach(Array(timeline.buffered.enumerated()), id: \.offset) { _, range in
                        Capsule().fill(.primary.opacity(0.14))
                            .frame(width: max(0, min(width, (range.upperBound - range.lowerBound) / duration * width)), height: 5)
                            .offset(x: min(width, max(0, range.lowerBound / duration * width)))
                    }
                    Capsule().fill(BMusicTheme.pink).frame(width: x, height: 5)
                    Circle().fill(BMusicTheme.pink)
                        .frame(width: hovering || timeline.isScrubbing ? 14 : 11, height: hovering || timeline.isScrubbing ? 14 : 11)
                        .position(x: x, y: geometry.size.height / 2)
                    if timeline.isScrubbing || hoverTime != nil {
                        VStack(spacing: 3) {
                            Text(TextFormatting.time(timeline.isScrubbing ? timeline.elapsed : (hoverTime ?? 0)))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            if fine && timeline.isScrubbing { Text("精细定位").font(.system(size: 9)) }
                        }
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .musicGlass(cornerRadius: 7)
                        .position(x: min(max(38, timeline.isScrubbing ? x : hoverX), max(38, width - 38)), y: -15)
                        .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hovering = true; hoverX = location.x - 6
                        hoverTime = min(duration, max(0, hoverX / width * duration))
                    case .ended: hovering = false; hoverTime = nil
                    }
                }
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard timeline.duration > 0 else { return }
                    let currentX = value.location.x - 6
                    let precise = abs(value.translation.height) > 38 || NSEvent.modifierFlags.contains(.shift)
                    if !tracking {
                        tracking = true; lastX = currentX
                        let anchorTime = min(duration, max(0, currentX / width * duration))
                        fine = precise
                        preview(anchorTime)
                    } else {
                        let scale = precise ? 0.1 : 1.0
                        let next = min(duration, max(0, timeline.elapsed + (currentX - lastX) / width * duration * scale))
                        lastX = currentX; fine = precise; preview(next)
                    }
                }.onEnded { _ in
                    guard tracking else { return }
                    let target = timeline.elapsed
                    tracking = false; fine = false; hoverTime = nil
                    commit(target)
                })
                .accessibilityElement()
                .accessibilityLabel("播放进度")
                .accessibilityValue(Text("\(TextFormatting.time(timeline.elapsed)) / \(TextFormatting.time(timeline.duration))"))
                .accessibilityAdjustableAction { direction in
                    commit(timeline.elapsed + (direction == .increment ? 5 : -5))
                }
                .help("点击或拖动定位；按住 Shift 或向下拖动可精细调整")
            }.frame(height: 24)
            ZStack(alignment: .leading) {
                if timeline.isSeeking { Text("定位中").foregroundStyle(BMusicTheme.pink) }
                else { Text(TextFormatting.time(timeline.duration)) }
            }.frame(width: 56, alignment: .leading)
        }
        .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
        .onChange(of: trackID) { tracking = false; hoverTime = nil; fine = false }
        .onDisappear { if timeline.isScrubbing { cancel() } }
    }
}
