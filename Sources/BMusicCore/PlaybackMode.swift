public enum PlaybackMode: String, Codable, CaseIterable, Sendable {
    case sequential, shuffle, repeatOne
    public var next: Self {
        switch self {
        case .sequential: return .shuffle
        case .shuffle: return .repeatOne
        case .repeatOne: return .sequential
        }
    }
    public var label: String {
        switch self {
        case .sequential: return "顺序播放"
        case .shuffle: return "随机播放"
        case .repeatOne: return "单曲循环"
        }
    }
    public var symbol: String {
        switch self {
        case .sequential: return "arrow.right"
        case .shuffle: return "shuffle"
        case .repeatOne: return "repeat.1"
        }
    }
}
