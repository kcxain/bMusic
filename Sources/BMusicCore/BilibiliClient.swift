import Foundation

public actor BilibiliClient {
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    private let session: URLSession
    private let responses = ResourcePool<String, Data>(concurrency: 4, budget: 768 * 1024,
                                                       countLimit: 20, lifetime: 60, cost: { $0.count })
    private var sessionEpoch = UUID()
    private let vault = SessionVault()
    private var keys: (String, String, Date)?
    private var bootstrapped = false
    private var detailCache: [String: (VideoDetails, Date)] = [:]
    private struct StoredCookie: Codable {
        let name: String; let value: String; let domain: String; let path: String; let expires: Date?
    }
    public init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.httpAdditionalHeaders = ["User-Agent": Self.userAgent, "Referer": "https://www.bilibili.com/"]
        config.urlCache = nil
        self.session = URLSession(configuration: config)
    }
    deinit { session.invalidateAndCancel() }
    public func restoreSession() throws {
        guard let data = try vault.read() else { return }
        let cookies = try JSONDecoder().decode([StoredCookie].self, from: data)
        for c in cookies {
            if let expiry = c.expires, expiry < Date() { continue }
            var properties: [HTTPCookiePropertyKey: Any] = [.name: c.name, .value: c.value, .domain: c.domain, .path: c.path, .secure: "TRUE"]
            if let expires = c.expires { properties[.expires] = expires }
            if let cookie = HTTPCookie(properties: properties) { session.configuration.httpCookieStorage?.setCookie(cookie) }
        }
    }
    private func saveSession() throws {
        let cookies = (session.configuration.httpCookieStorage?.cookies ?? []).filter { $0.domain == "bilibili.com" || $0.domain.hasSuffix(".bilibili.com") }
        let stored = cookies.map { StoredCookie(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path, expires: $0.expiresDate) }
        try vault.write(JSONEncoder().encode(stored))
    }
    public func logout() throws {
        try vault.delete()
        session.configuration.httpCookieStorage?.removeCookies(since: .distantPast)
        keys = nil; bootstrapped = false; sessionEpoch = UUID()
    }
    private func bootstrap() async throws {
        guard !bootstrapped else { return }
        let (_, response) = try await session.data(from: URL(string: "https://www.bilibili.com/")!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        bootstrapped = true
    }
    private func request(_ path: String, parameters: [String: String] = [:], signed: Bool = false, allowLoggedOut: Bool = false) async throws -> [String: Any] {
        let base = path.hasPrefix("https://") ? path : "https://api.bilibili.com" + path
        var components = URLComponents(string: base)!
        if signed {
            let (image, sub) = try await signingKeys()
            components.percentEncodedQuery = try WBISigner.query(parameters, imageKey: image, subKey: sub)
        } else if !parameters.isEmpty {
            components.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        let url = components.url!, session = session
        let operation: @Sendable () async throws -> Data = {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { throw BMusicError.invalidResponse }
            guard http.statusCode == 200 else { throw BMusicError.api(http.statusCode, "HTTP 请求失败") }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let code = json["code"] as? Int else { throw BMusicError.invalidResponse }
            guard code == 0 || (allowLoggedOut && code == -101) else {
                throw BMusicError.api(code, json["message"] as? String ?? "请求失败")
            }
            if (json["data"] as? [String: Any])?["v_voucher"] != nil { throw BMusicError.api(-352, "请求需要验证") }
            return data
        }
        let cacheable = ["/x/web-interface/nav", "/x/web-interface/view", "/x/web-interface/wbi/search/type", "/x/web-interface/ranking/v2"].contains(path)
        let key = sessionEpoch.uuidString + base + parameters.sorted { $0.key < $1.key }.map { "\($0.key.utf8.count):\($0.key)\($0.value.utf8.count):\($0.value)" }.joined()
        let data: Data
        if cacheable { data = try await responses.value(for: key, operation: operation) }
        else { data = try await operation() }
        try Task.checkCancellation()
        return try Self.responseData(data, allowLoggedOut: allowLoggedOut)
    }
    private static func responseData(_ data: Data, allowLoggedOut: Bool) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let code = json["code"] as? Int else { throw BMusicError.invalidResponse }
        guard code == 0 || (allowLoggedOut && code == -101) else { throw BMusicError.api(code, json["message"] as? String ?? "请求失败") }
        return json["data"] as? [String: Any] ?? [:]
    }
    private func signingKeys() async throws -> (String, String) {
        if let (image, sub, date) = keys, Date().timeIntervalSince(date) < 1800 { return (image, sub) }
        let data = try await request("/x/web-interface/nav", allowLoggedOut: true)
        rememberSigningKeys(data)
        guard let (image, sub, _) = keys else { throw BMusicError.invalidResponse }
        return (image, sub)
    }
    private func rememberSigningKeys(_ data: [String: Any]) {
        guard let images = data["wbi_img"] as? [String: String],
              let image = images["img_url"].flatMap(URL.init(string:)),
              let sub = images["sub_url"].flatMap(URL.init(string:)) else { return }
        keys = (image.deletingPathExtension().lastPathComponent, sub.deletingPathExtension().lastPathComponent, Date())
    }
    public func profile() async throws -> UserProfile? {
        let data = try await request("/x/web-interface/nav", allowLoggedOut: true)
        rememberSigningKeys(data)
        guard data["isLogin"] as? Bool == true else { return nil }
        let vip = data["vipStatus"] as? Int ?? (data["vip"] as? [String: Any])?["status"] as? Int ?? 0
        return UserProfile(id: (data["mid"] as? NSNumber)?.int64Value ?? 0, name: data["uname"] as? String ?? "B 站用户", avatar: TextFormatting.imageURL(data["face"] as? String ?? ""), isVIP: vip == 1)
    }
    public func generateQR() async throws -> QRCode {
        let data = try await request("https://passport.bilibili.com/x/passport-login/web/qrcode/generate")
        guard let url = data["url"] as? String, let key = data["qrcode_key"] as? String else { throw BMusicError.invalidResponse }
        return QRCode(url: url, key: key)
    }
    public func pollQR(key: String) async throws -> QRStatus {
        let data = try await request("https://passport.bilibili.com/x/passport-login/web/qrcode/poll", parameters: ["qrcode_key": key])
        switch data["code"] as? Int {
        case 86101: return .waiting
        case 86090: return .scanned
        case 86038: return .expired
        case 0:
            // Set-Cookie is normally handled by URLSession. The callback also carries credentials.
            if let raw = data["url"] as? String, let url = URLComponents(string: raw) {
                for item in url.queryItems ?? [] where ["SESSDATA", "bili_jct", "DedeUserID", "DedeUserID__ckMd5"].contains(item.name) {
                    guard let value = item.value, let cookie = HTTPCookie(properties: [.name: item.name, .value: value, .domain: ".bilibili.com", .path: "/", .secure: "TRUE", .expires: Date().addingTimeInterval(180 * 86400)]) else { continue }
                    session.configuration.httpCookieStorage?.setCookie(cookie)
                }
            }
            try saveSession(); keys = nil; sessionEpoch = UUID()
            return .confirmed
        default: throw BMusicError.invalidResponse
        }
    }
    public func musicRanking() async throws -> [Track] {
        let data = try await request("/x/web-interface/ranking/v2", parameters: ["rid": "3", "type": "all"])
        guard let rows = data["list"] as? [[String: Any]] else { throw BMusicError.invalidResponse }
        return rows.prefix(12).compactMap { row in
            guard let bvid = row["bvid"] as? String else { return nil }
            let owner = row["owner"] as? [String: Any] ?? [:]
            return Track(bvid: bvid, cid: (row["cid"] as? NSNumber)?.int64Value,
                         title: TextFormatting.cleanTitle(row["title"] as? String ?? ""),
                         uploader: owner["name"] as? String ?? "",
                         cover: TextFormatting.imageURL(row["pic"] as? String ?? ""),
                         duration: (row["duration"] as? NSNumber)?.doubleValue ?? 0)
        }
    }
    public func search(_ keyword: String, page: Int = 1, musicOnly: Bool = true) async throws -> SearchPage {
        async let cookies: Void = bootstrap()
        async let signing = signingKeys()
        _ = try await (cookies, signing)
        let data = try await request("/x/web-interface/wbi/search/type", parameters: ["search_type": "video", "keyword": keyword, "page": String(page), "page_size": "20", "order": "totalrank", "tids": musicOnly ? "3" : "0"], signed: true)
        if data["v_voucher"] != nil { throw BMusicError.api(-352, "请求需要验证") }
        let tracks = (data["result"] as? [[String: Any]] ?? []).compactMap { row -> Track? in
            guard let bvid = row["bvid"] as? String, bvid.hasPrefix("BV") else { return nil }
            return Track(bvid: bvid, title: TextFormatting.cleanTitle(row["title"] as? String ?? "未命名"), uploader: row["author"] as? String ?? "", cover: TextFormatting.imageURL(row["pic"] as? String ?? ""), duration: TextFormatting.seconds(row["duration"] as? String ?? "0"))
        }
        return SearchPage(tracks: tracks, totalPages: data["numPages"] as? Int ?? 1)
    }
    public func details(_ track: Track) async throws -> VideoDetails {
        if let (details, date) = detailCache[track.bvid], Date().timeIntervalSince(date) < 900 { return details }
        let data = try await request("/x/web-interface/view", parameters: ["bvid": track.bvid])
        let owner = data["owner"] as? [String: Any] ?? [:]
        let title = data["title"] as? String ?? track.title
        let pages = data["pages"] as? [[String: Any]] ?? []
        let tracks = pages.compactMap { page -> Track? in
            guard let cid = (page["cid"] as? NSNumber)?.int64Value else { return nil }
            let part = page["page"] as? Int ?? 1
            return Track(bvid: track.bvid, cid: cid, title: pages.count > 1 ? "\(title) · \(page["part"] as? String ?? "P\(part)")" : title, uploader: owner["name"] as? String ?? track.uploader, cover: TextFormatting.imageURL(data["pic"] as? String ?? "") ?? track.cover, duration: (page["duration"] as? NSNumber)?.doubleValue ?? track.duration, part: part)
        }
        guard !tracks.isEmpty else { throw BMusicError.invalidResponse }
        let details = VideoDetails(tracks: tracks)
        if detailCache.count >= 32, let oldest = detailCache.min(by: { $0.value.1 < $1.value.1 })?.key {
            detailCache.removeValue(forKey: oldest)
        }
        // Bound decoded metadata as well as response bytes, including multi-part collections.
        while detailCache.values.reduce(0, { $0 + $1.0.tracks.count }) + tracks.count > 1000 {
            guard let oldest = detailCache.min(by: { $0.value.1 < $1.value.1 })?.key else { break }
            detailCache.removeValue(forKey: oldest)
        }
        if tracks.count <= 1000 { detailCache[track.bvid] = (details, Date()) }
        return details
    }
    public func audio(_ track: Track) async throws -> [AudioStream] {
        guard let cid = track.cid else { throw BMusicError.invalidResponse }
        let data = try await request("/x/player/wbi/playurl", parameters: ["bvid": track.bvid, "cid": String(cid), "fnval": "4048", "fnver": "0", "fourk": "1"], signed: true)
        return try Self.parseAudio(data)
    }
    public static func parseAudio(_ data: [String: Any]) throws -> [AudioStream] {
        guard let dash = data["dash"] as? [String: Any] else { throw BMusicError.noAudio }
        var rows = dash["audio"] as? [[String: Any]] ?? []
        if let flac = dash["flac"] as? [String: Any], let audio = flac["audio"] as? [String: Any] { rows.append(audio) }
        if let dolby = dash["dolby"] as? [String: Any], let audio = dolby["audio"] as? [[String: Any]] { rows += audio }
        var seen: Set<Int> = []
        let result = rows.compactMap { row -> AudioStream? in
            guard let id = row["id"] as? Int, let raw = (row["baseUrl"] ?? row["base_url"]) as? String, let url = URL(string: raw), url.scheme == "https" || url.scheme == "http", seen.insert(id).inserted else { return nil }
            let backups = ((row["backupUrl"] ?? row["backup_url"]) as? [String] ?? []).compactMap(URL.init(string:))
            return AudioStream(id: id, url: url, backups: backups, bandwidth: row["bandwidth"] as? Int ?? 0, codec: row["codecs"] as? String ?? "")
        }.sorted { $0.rank > $1.rank }
        guard !result.isEmpty else { throw BMusicError.noAudio }
        return result
    }
}
