import Foundation

public struct Track: Codable, Hashable, Identifiable, Sendable {
    public let bvid: String
    public var cid: Int64?
    public var title: String
    public var uploader: String
    public var cover: URL?
    public var duration: Double
    public var part: Int
    public var id: String { "\(bvid):\(part)" }
    public var webURL: URL { URL(string: "https://www.bilibili.com/video/\(bvid)?p=\(part)")! }
    public init(bvid: String, cid: Int64? = nil, title: String, uploader: String, cover: URL? = nil, duration: Double = 0, part: Int = 1) {
        self.bvid = bvid; self.cid = cid; self.title = title; self.uploader = uploader
        self.cover = cover; self.duration = duration; self.part = part
    }
}

public struct Playlist: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var tracks: [Track]
    public init(id: UUID = UUID(), name: String, tracks: [Track] = []) {
        self.id = id; self.name = name; self.tracks = tracks
    }
}

public struct Library: Codable, Equatable, Sendable {
    public var favorites: [Track] = []
    public var playlists: [Playlist] = []
    public var recent: [Track] = []
    public init() {}
    public mutating func toggleFavorite(_ track: Track) {
        if favorites.contains(where: { $0.id == track.id }) { favorites.removeAll { $0.id == track.id } }
        else { favorites.insert(track, at: 0) }
    }
    public mutating func add(_ track: Track, to playlist: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist }),
              !playlists[index].tracks.contains(where: { $0.id == track.id }) else { return }
        playlists[index].tracks.append(track)
    }
    public mutating func record(_ track: Track) {
        recent.removeAll { $0.id == track.id }; recent.insert(track, at: 0)
        recent = Array(recent.prefix(100))
    }
}

public struct AudioStream: Identifiable, Sendable, Equatable {
    public let id: Int
    public let url: URL
    public let backups: [URL]
    public let bandwidth: Int
    public let codec: String
    public init(id: Int, url: URL, backups: [URL] = [], bandwidth: Int, codec: String) {
        self.id = id; self.url = url; self.backups = backups; self.bandwidth = bandwidth; self.codec = codec
    }
    public var isHiRes: Bool { id == 30251 }
    public var label: String {
        switch id {
        case 30251: return "Hi-Res 无损"
        case 30250: return "Dolby 音轨"
        case 30280: return "高音质"
        case 30232: return "标准"
        case 30216: return "流畅"
        default: return "音频 \(id)"
        }
    }
    public var detail: String { "\(label) · \(bandwidth / 1000) kbps · \(codec)" }
    public var rank: Int {
        switch id { case 30251: return 5; case 30250: return 4; case 30280: return 3; case 30232: return 2; default: return 1 }
    }
    public static func preferred(in streams: [AudioStream], hiRes: Bool) -> AudioStream? {
        let candidates = hiRes ? streams : streams.filter { !$0.isHiRes && $0.id != 30250 }
        return (candidates.isEmpty ? streams : candidates).max { ($0.rank, $0.bandwidth) < ($1.rank, $1.bandwidth) }
    }
}

public struct UserProfile: Sendable {
    public let id: Int64
    public let name: String
    public let avatar: URL?
    public let isVIP: Bool
}
public struct QRCode: Sendable { public let url: String; public let key: String }
public enum QRStatus: Sendable { case waiting, scanned, expired, confirmed }
public struct SearchPage: Sendable { public let tracks: [Track]; public let totalPages: Int }
public struct VideoDetails: Sendable { public let tracks: [Track] }

public enum BMusicError: LocalizedError {
    case api(Int, String), invalidResponse, noAudio, storage(String)
    public var errorDescription: String? {
        switch self {
        case let .api(code, message):
            switch code {
            case -101: return "登录已过期，请重新扫码登录。"
            case -352, -412, 412: return "B 站暂时限制了请求，请稍后重试，或登录后再试。"
            case -404, 62002: return "该视频已失效或暂时无法访问。"
            default: return "B 站返回：\(message)（\(code)）"
            }
        case .invalidResponse: return "服务返回了无法识别的数据，请稍后重试。"
        case .noAudio: return "该视频暂未提供可播放的独立音频流。"
        case .storage(let message): return "保存失败：\(message)"
        }
    }
}

public enum TextFormatting {
    public static func cleanTitle(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, value) in [("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result
    }
    public static func seconds(_ text: String) -> Double {
        text.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }
    public static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let s = Int(seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
    public static func imageURL(_ value: String) -> URL? {
        URL(string: value.hasPrefix("//") ? "https:" + value : value.replacingOccurrences(of: "http://", with: "https://"))
    }
}
