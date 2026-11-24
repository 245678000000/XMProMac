import Foundation

/// 喜马拉雅核心客户端：搜索、专辑/声音拉取、音频流解密、听时查询与扣时上报
public final class XmlyClient: @unchecked Sendable {
    public static let mobileOrigin = "https://mobile.ximalaya.com"
    public static let webOrigin = "https://www.ximalaya.com"
    public static let collectorOrigin = "https://xdcs-collector.ximalaya.com"
    public static let welfareOrigin = "https://m.ximalaya.com"
    public static let anonymousIdentity = "anonymous"
    public static let parallelPageFetch = 4

    public let http: XmlyHttp
    public let credentials: Credentials?
    public let mobile: String
    public let searchOrigin: String
    public let collector: String
    public let clock: ServerClock

    public var identity: String { credentials?.identity ?? Self.anonymousIdentity }
    public var accountAvailable: Bool { credentials != nil }

    public init(
        http: XmlyHttp = XmlyHttp(),
        credentials: Credentials? = nil,
        clock: ServerClock = .shared,
        mobile: String = XmlyClient.mobileOrigin,
        searchOrigin: String = XmlyHttp.searchOrigin,
        collector: String = XmlyClient.collectorOrigin
    ) {
        self.http = http
        self.credentials = credentials
        self.clock = clock
        self.mobile = mobile
        self.searchOrigin = searchOrigin
        self.collector = collector
    }

    public static func originHeaders(for origin: String) -> [String: String] {
        if origin == collectorOrigin {
            return [
                "User-Agent": "ting_3.4.10.3(Android,30)",
                "Accept": "*/*",
            ]
        }
        return [:]
    }

    /// 未登录公共移动端 GET 请求
    public func getMobile(path: String, query: [String: String] = [:]) async throws -> [String: Any] {
        try await http.get(origin: mobile, path: path, query: query)
    }

    /// 绑定当前账号的通用极速版请求入口
    public func request(
        method: String,
        origin: String,
        path: String,
        query: [String: String] = [:],
        form: [String: String]? = nil,
        json: [String: Any]? = nil,
        account: Bool = true,
        readOnly: Bool = true,
        signed: Bool = false,
        headers: [String: String] = [:]
    ) async throws -> [String: Any] {
        let bound = account ? credentials : nil
        if account && bound == nil {
            throw XmlyException(code: "login_required", message: "请先登录", definitive: true)
        }
        var merged = Self.originHeaders(for: origin)
        for (k, v) in headers {
            merged[k] = v
        }
        let limit = (origin == Self.collectorOrigin) ? 8 * 1024 * 1024 : XmlyHttp.maxResponseBytes
        if method == "GET" {
            return try await http.get(
                origin: origin,
                path: path,
                query: query,
                credentials: bound,
                signed: signed,
                readOnly: readOnly,
                headers: merged,
                responseLimit: limit
            )
        } else if let form {
            return try await http.postForm(
                origin: origin,
                path: path,
                query: query,
                form: form,
                credentials: bound,
                signed: signed,
                readOnly: readOnly,
                responseLimit: limit,
                headers: merged
            )
        } else {
            return try await http.postJson(
                origin: origin,
                path: path,
                query: query,
                json: json ?? [:],
                credentials: bound,
                signed: signed,
                readOnly: readOnly,
                responseLimit: limit,
                headers: merged
            )
        }
    }

    /// 云端历史签名所需的账号上下文字段
    public func context() throws -> [String: String] {
        guard let account = credentials else {
            throw XmlyException(code: "login_required", message: "历史同步需要登录", definitive: true)
        }
        return [
            "uid": account.uid,
            "token": account.tokenSecret,
            "device": "android",
            "deviceId": account.deviceId,
            "version": "3.4.10",
            "channel": "and-f5",
            "impl": "com.ximalaya.ting.lite",
        ]
    }

    // MARK: - 搜索与专辑目录

    public func search(
        query: String,
        kind: String = "album",
        page: Int = 1,
        pageSize: Int = 20
    ) async throws -> SearchPage {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200, kind == "track" || kind == "album" else {
            throw XmlyException(code: "invalid_search", message: "请输入 1..200 字的关键词", definitive: true)
        }
        try validatePaging(page: page, pageSize: pageSize)
        let payload = try await http.get(
            origin: searchOrigin,
            path: "/revision/search",
            query: [
                "kw": trimmed,
                "core": kind,
                "page": String(page),
                "rows": String(pageSize),
                "device": "iPhone",
                "condition": "relation",
                "spellchecker": "true",
            ]
        )
        guard let data = payload["data"] as? [String: Any],
              let result = data["result"] as? [String: Any],
              let response = result["response"] as? [String: Any],
              let docs = response["docs"] as? [[String: Any]] else {
            throw XmlyException(code: "invalid_catalogue", message: "搜索结果无效")
        }

        var tracks: [Track] = []
        var albums: [Album] = []
        for raw in docs.prefix(pageSize) {
            if kind == "album" {
                let idText = JSONHelpers.string(raw["albumId"] ?? raw["id"])
                guard !idText.isEmpty, let normId = try? XmlyIdentifiers.xmlyIdentifier(idText) else { continue }
                let count = JSONHelpers.int(raw["tracks"] ?? raw["totalCount"] ?? raw["trackCount"]) ?? 0
                if let album = try? albumFromApi(raw, id: normId, total: count) {
                    albums.append(album)
                }
            } else {
                if let track = trackFromApi(raw) {
                    tracks.append(track)
                }
            }
        }
        let total = JSONHelpers.int(response["numFound"]) ?? docs.count
        return SearchPage(
            tracks: tracks,
            albums: albums,
            page: page,
            pageSize: pageSize,
            total: total,
            kind: kind
        )
    }

    /// 定位包含某声音的专辑分页（优先依据剧集提示页码，再按批量并发查找）
    public func albumPageWith(
        albumId: String,
        trackId: String,
        hintOrdinal: Int? = nil,
        maxPages: Int = 60
    ) async throws -> AlbumPage? {
        let wanted = "xmly:\((try? XmlyIdentifiers.xmlyIdentifier(trackId)) ?? trackId)"
        func holds(_ page: AlbumPage) -> Bool {
            page.tracks.contains { $0.id == wanted }
        }

        if let hint = hintOrdinal, hint > 0 {
            let candidate = (hint - 1) / xmlyAlbumPageSize + 1
            if candidate <= maxPages {
                if let page = try? await album(albumId: albumId, page: candidate), holds(page) {
                    return page
                }
            }
        }

        let first = try await album(albumId: albumId, page: 1)
        if holds(first) { return first }

        let totalPages = min((first.total + first.pageSize - 1) / first.pageSize, maxPages)
        var pageIndex = 2
        while pageIndex <= totalPages {
            let batchEnd = min(pageIndex + Self.parallelPageFetch - 1, totalPages)
            let batch = Array(pageIndex...batchEnd)
            let fetched: [AlbumPage?] = await withTaskGroup(of: (Int, AlbumPage?).self) { group in
                for p in batch {
                    group.addTask {
                        let res = try? await self.album(albumId: albumId, page: p)
                        return (p, res)
                    }
                }
                var map: [Int: AlbumPage] = [:]
                for await (p, res) in group {
                    if let res { map[p] = res }
                }
                return batch.map { map[$0] }
            }
            if let hit = fetched.compactMap({ $0 }).first(where: holds) {
                return hit
            }
            pageIndex += batch.count
        }
        return nil
    }

    /// 获取专辑单页剧集列表及专辑详情头部信息
    public func album(
        albumId: String,
        page: Int = 1,
        pageSize: Int = xmlyAlbumPageSize,
        ascending: Bool = true
    ) async throws -> AlbumPage {
        let number = try XmlyIdentifiers.xmlyIdentifier(albumId)
        try validatePaging(page: page, pageSize: pageSize, maxPageSize: xmlyAlbumPageSize)

        let payload = try await http.get(
            origin: mobile,
            path: "/mobile/v1/album/track/v2",
            query: [
                "albumId": number,
                "pageId": String(page),
                "pageSize": String(pageSize),
                "isAsc": ascending ? "true" : "false",
                "device": "android",
                "isQueryInvitationBrand": "true",
            ]
        )
        guard let data = payload["data"] as? [String: Any],
              let list = data["list"] as? [[String: Any]] else {
            throw XmlyException(code: "invalid_catalogue", message: "专辑列表无效")
        }
        let total = try parseNonNegativeTotal(data["totalCount"], message: "专辑分页总数无效")
        if let respPage = data["pageId"], try parseNonNegativeTotal(respPage, message: "专辑分页无效") != page {
            throw XmlyException(code: "invalid_catalogue", message: "专辑分页无效")
        }
        if let respSize = data["pageSize"], try parseNonNegativeTotal(respSize, message: "专辑分页无效") != pageSize {
            throw XmlyException(code: "invalid_catalogue", message: "专辑分页无效")
        }
        let expected = min(max(total - (page - 1) * pageSize, 0), pageSize)
        if list.count > pageSize || (list.isEmpty && expected > 0) {
            throw XmlyException(code: "incomplete_catalogue", message: "专辑分页不完整，请刷新重试")
        }

        if let albumObj = payload["album"] as? [String: Any], let rawAlbumId = albumObj["albumId"] {
            if try XmlyIdentifiers.xmlyIdentifier(JSONHelpers.string(rawAlbumId)) != number {
                throw XmlyException(code: "id_mismatch", message: "专辑信息不匹配")
            }
        }
        if let rawDataAlbumId = data["albumId"] {
            if try XmlyIdentifiers.xmlyIdentifier(JSONHelpers.string(rawDataAlbumId)) != number {
                throw XmlyException(code: "id_mismatch", message: "专辑信息不匹配")
            }
        }

        var seen = Set<String>()
        var tracks: [Track] = []
        tracks.reserveCapacity(list.count)
        for (index, raw) in list.enumerated() {
            for key in ["albumId", "album_id"] {
                if let v = raw[key] {
                    let s = JSONHelpers.string(v)
                    if !s.isEmpty, try XmlyIdentifiers.xmlyIdentifier(s) != number {
                        throw XmlyException(code: "id_mismatch", message: "专辑包含其他专辑的声音")
                    }
                }
            }
            let tid = try XmlyIdentifiers.xmlyIdentifier(JSONHelpers.string(raw["trackId"] ?? raw["id"]))
            guard seen.insert(tid).inserted else {
                throw XmlyException(code: "duplicate_page", message: "专辑声音重复，请刷新重试")
            }
            let position = (page - 1) * pageSize + index + 1
            let official: Int? = ascending ? position : (total > 0 ? total - position + 1 : nil)
            if let track = trackFromApi(raw, albumId: number, officialPosition: official) {
                tracks.append(track)
            }
        }

        var mergedAlbumMap = (payload["album"] as? [String: Any]) ?? data
        let detail = await albumDetail(albumId: number)
        for (k, v) in detail {
            mergedAlbumMap[k] = v
        }
        var parsedAlbum = try albumFromApi(mergedAlbumMap, id: number, total: total)
        if parsedAlbum.title.isEmpty, let fromTrack = tracks.first(where: { !$0.album.isEmpty })?.album {
            parsedAlbum = try Album(
                rawId: parsedAlbum.id,
                title: fromTrack,
                artist: parsedAlbum.artist,
                intro: parsedAlbum.intro,
                coverUrl: parsedAlbum.coverUrl,
                total: parsedAlbum.total
            )
        }
        return AlbumPage(album: parsedAlbum, tracks: tracks, page: page, pageSize: pageSize, total: total)
    }

    /// 获取专辑总集数（订阅列表不含集数，可按需补充）
    public func albumTrackCount(albumId: String) async -> Int {
        guard let id = try? XmlyIdentifiers.xmlyIdentifier(albumId) else { return 0 }
        guard let payload = try? await http.get(
            origin: mobile,
            path: "/mobile/v1/album/track/v2",
            query: [
                "albumId": id,
                "pageId": "1",
                "pageSize": "1",
                "isAsc": "true",
                "device": "android",
            ]
        ),
              let data = payload["data"] as? [String: Any] else {
            return 0
        }
        return JSONHelpers.int(data["totalCount"]) ?? 0
    }

    private func albumDetail(albumId: String) async -> [String: Any] {
        guard let payload = try? await http.get(
            origin: mobile,
            path: "/mobile-album/album/detail",
            query: ["albumId": albumId, "device": "android"]
        ),
              let data = payload["data"] as? [String: Any],
              var info = data["album"] as? [String: Any] else {
            return [:]
        }
        if let user = data["user"] as? [String: Any] {
            if let nick = user["nickname"] as? String { info["nickname"] = nick }
            if let avatar = user["avatar"] as? String { info["avatar"] = avatar }
        }
        if let detail = data["detail"] as? [String: Any],
           let intro = detail["intro"] as? String, !intro.isEmpty {
            info["intro"] = intro
        }
        if let title = info["title"] as? String, !title.isEmpty {
            info["albumTitle"] = title
        }
        return info
    }

    // MARK: - 声音详情与播放地址解析

    public func track(number: String) async throws -> Track {
        let id = try XmlyIdentifiers.xmlyIdentifier(number)
        let map = try await trackInfoMap(id: id)
        guard let track = trackFromApi(map) else {
            throw XmlyException(code: "missing_track", message: "声音信息缺失")
        }
        return track
    }

    /// 解析并解密声音的最佳可播放 HTTPS CDN 直链
    public func resolve(number: String, quality: String = "auto") async throws -> ResolvedAudio {
        let requested = (quality == "auto") ? "auto" : quality.lowercased()
        if requested != "auto" && !xmlyQualities.contains(requested) {
            throw XmlyException(code: "invalid_quality", message: "音质设置无效", definitive: true)
        }

        let id = try XmlyIdentifiers.xmlyIdentifier(number)
        var info = try await trackInfoMap(id: id)
        var requiresReward = false

        let isPaid = JSONHelpers.bool(info["isPaid"])
        let isAuthorized = JSONHelpers.bool(info["isAuthorized"])
        if isPaid != false && isAuthorized != true {
            guard let account = credentials else {
                throw XmlyException(code: "login_required", message: "请先导入或登录极速版账号", definitive: true)
            }
            let currentQuota = try await activity(name: "config", seconds: nil)
            if !currentQuota.newDevice && currentQuota.remainingSeconds <= 0 {
                throw XmlyException(code: "insufficient_quota", message: "听时不足，请领取听时或在官方 App 补充", definitive: true)
            }
            requiresReward = true
            info = try await trackInfoMap(id: id, reward: currentQuota)
            if JSONHelpers.bool(info["isPaid"]) == false || JSONHelpers.bool(info["isAuthorized"]) == true {
                requiresReward = false
            }
            if account.uid.isEmpty {
                throw XmlyException(code: "login_required", message: "请先登录", definitive: true)
            }
        }

        if JSONHelpers.bool(info["isPreview"]) == true || JSONHelpers.bool(info["isTrial"]) == true {
            throw XmlyException(code: "preview_only", message: "仅获得试听音频，无法播放完整声音", definitive: true)
        }

        var candidates: [String: String] = [:]
        func addCandidate(type: String, value: Any?, encrypted: Bool) throws {
            guard let text = value as? String, !text.isEmpty, candidates[type] == nil else { return }
            let decoded: String
            if encrypted && !text.hasPrefix("http://") && !text.hasPrefix("https://") {
                decoded = try XmlyCrypto.decrypt(text, key: XmlyCrypto.playKey)
            } else {
                decoded = text
            }
            candidates[type] = try XmlyIdentifiers.mediaUri(decoded)
        }

        let accountPresent = credentials != nil
        if accountPresent, let rawList = info["playUrlList"] {
            let list: [[String: Any]]
            if let arr = rawList as? [[String: Any]] {
                list = arr
            } else if let str = rawList as? String,
                      let data = str.data(using: .utf8),
                      let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                list = parsed
            } else {
                throw XmlyException(code: "invalid_media", message: "音频列表格式无效")
            }
            for item in list {
                let type = JSONHelpers.string(item["type"]).lowercased()
                guard xmlyQualities.contains(type) else { continue }
                try addCandidate(type: type, value: item["url"], encrypted: true)
            }
        }
        if !accountPresent || candidates.isEmpty {
            try addCandidate(type: "mp3_64", value: info["playUrl64"], encrypted: true)
            try addCandidate(type: "mp3_32", value: info["playUrl32"], encrypted: true)
        }

        guard !candidates.isEmpty else {
            throw XmlyException(
                code: "permission_denied",
                message: "当前没有获得完整音频地址，请检查听时与版权权限",
                definitive: true
            )
        }

        let chosen: String
        if requested != "auto", candidates[requested] != nil {
            chosen = requested
        } else if let best = xmlyQualities.first(where: { candidates[$0] != nil }) {
            chosen = best
        } else {
            chosen = candidates.keys.first!
        }

        guard let track = trackFromApi(info) else {
            throw XmlyException(code: "missing_track", message: "声音信息缺失")
        }
        var finalUrl = candidates[chosen]!
        if !finalUrl.contains(".xmcdn.com/") {
            let redirected = await http.followRedirect(url: finalUrl)
            finalUrl = try XmlyIdentifiers.mediaUri(redirected)
        }
        return ResolvedAudio(
            url: finalUrl,
            headers: [:],
            requiresReward: requiresReward,
            track: track,
            actualQuality: chosen,
            accountIdentity: identity
        )
    }

    private func trackInfoMap(id: String, reward: Quota? = nil) async throws -> [String: Any] {
        guard let account = credentials else {
            let payload = try await http.get(
                origin: mobile,
                path: "/mobile/track/\(id)",
                query: ["device": "android"]
            )
            let obj = (payload["data"] as? [String: Any]) ?? payload
            return try matchingInfo(obj, id: id)
        }

        var params: [String: Any] = [
            "device": "android",
            "trackId": id,
        ]
        if let reward {
            // a1 超过一天会被服务端 ret=4 拒绝，需截断到单日上限
            params["a1"] = reward.newDevice
                ? "1"
                : String(min(max(reward.remainingSeconds, 0), xmlyMaxUsageSeconds))
            params["a2"] = String(clock.nowMillis())
            params["a3"] = "0"
        }
        let jsonData = try JSONSerialization.data(withJSONObject: params, options: [])
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        let encrypted = try XmlyCrypto.encrypt(jsonString, key: XmlyCrypto.playKey)
        let payload = try await http.postJson(
            origin: mobile,
            path: "/fmobile-track/fmobile/track/v2/baseInfo",
            json: ["data": encrypted],
            credentials: account,
            signed: true,
            readOnly: true
        )
        guard let body = payload["data"] as? String else {
            throw XmlyException(code: "invalid_authorization", message: "授权声音信息无效")
        }
        let decrypted = try XmlyCrypto.decrypt(body, key: XmlyCrypto.playKey)
        guard let decData = decrypted.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: decData) as? [String: Any] else {
            throw XmlyException(code: "invalid_authorization", message: "授权声音信息无效")
        }
        let infoObj: [String: Any]?
        if let dict = decoded["trackInfo"] as? [String: Any] {
            infoObj = dict
        } else if let str = decoded["trackInfo"] as? String,
                  let d = str.data(using: .utf8) {
            infoObj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
        } else {
            infoObj = nil
        }
        guard let validInfo = infoObj else {
            throw XmlyException(code: "invalid_authorization", message: "授权声音信息无效")
        }
        return try matchingInfo(validInfo, id: id)
    }

    private func matchingInfo(_ map: [String: Any], id: String) throws -> [String: Any] {
        let returned = JSONHelpers.string(map["trackId"] ?? map["id"])
        if !returned.isEmpty, try XmlyIdentifiers.xmlyIdentifier(returned) != id {
            throw XmlyException(code: "id_mismatch", message: "声音信息不匹配")
        }
        return map
    }

    // MARK: - 听时查询与扣时

    public func quota() async throws -> Quota {
        try await activity(name: "config", seconds: nil)
    }

    public func debit(seconds: Int) async throws -> Quota {
        guard seconds >= 1 else {
            throw XmlyException(code: "invalid_duration", message: "听时必须为正整数秒", definitive: true)
        }
        return try await activity(name: "report", seconds: seconds)
    }

    private func activity(name: String, seconds: Int?) async throws -> Quota {
        guard let account = credentials else {
            throw XmlyException(code: "login_required", message: "请先登录", definitive: true)
        }
        var params: [String: String] = [
            "deviceId": account.deviceId,
            "timestamp": String(clock.nowMillis()),
            "uid": account.uid,
        ]
        if let seconds {
            params["duration"] = String(seconds)
        }
        let signature = XmlyCrypto.activitySignature(params)
        var body: [String: Any] = ["signature": signature]
        for (k, v) in params where k != "uid" {
            body[k] = v
        }
        let payload = try await http.postJson(
            origin: mobile,
            path: "/lite-mobile/audi/func/v1/\(name)",
            json: body,
            credentials: account,
            readOnly: name == "config"
        )
        guard let data = payload["data"] as? [String: Any] else {
            throw XmlyException(code: "invalid_quota", message: "听时信息缺失或已过期")
        }
        func decodeField(_ field: String) throws -> String {
            guard let raw = data[field] as? String else {
                throw XmlyException(code: "invalid_quota", message: "听时信息缺失或已过期")
            }
            let plain = try XmlyCrypto.decrypt(raw, key: XmlyCrypto.durationKey)
            guard let divider = plain.lastIndex(of: "|") else {
                throw XmlyException(code: "invalid_quota", message: "听时信息缺失或已过期")
            }
            let stampText = String(plain[plain.index(after: divider)...])
            guard let stamp = Int64(stampText), abs(clock.nowMillis() - stamp) < 180_000 else {
                throw XmlyException(code: "invalid_quota", message: "听时信息缺失或已过期")
            }
            return String(plain[..<divider])
        }

        var newDevice = false
        if name == "config" {
            let flag = try decodeField("newDevice")
            guard flag == "true" || flag == "false" else {
                throw XmlyException(code: "invalid_quota", message: "设备授权信息无效")
            }
            newDevice = (flag == "true")
        }
        let remaining: Int
        if newDevice && data["availableListenDuration"] == nil {
            remaining = 0
        } else {
            guard let parsed = Int(try decodeField("availableListenDuration")), parsed >= 0 else {
                throw XmlyException(code: "invalid_quota", message: "听时余额无效")
            }
            remaining = parsed
        }
        return Quota(remainingSeconds: remaining, newDevice: newDevice, checkedAt: clock.nowDate())
    }

    // MARK: - 模型解析辅助

    private func validatePaging(page: Int, pageSize: Int, maxPageSize: Int = 50) throws {
        guard (1...10000).contains(page), (1...maxPageSize).contains(pageSize) else {
            throw XmlyException(
                code: "invalid_page",
                message: "页码范围为 1..10000，每页 1..\(maxPageSize)",
                definitive: true
            )
        }
    }

    private func parseNonNegativeTotal(_ value: Any?, message: String) throws -> Int {
        guard let num = JSONHelpers.double(value),
              num.isFinite, num >= 0, floor(num) == num else {
            throw XmlyException(code: "invalid_page", message: message)
        }
        return Int(num)
    }

    private func albumFromApi(_ raw: [String: Any], id: String, total: Int = 0) throws -> Album {
        let title = JSONHelpers.string(raw["albumTitle"] ?? raw["album_title"] ?? raw["title"])
        let artist = JSONHelpers.string(raw["nickname"] ?? raw["artist"])
        let intro = JSONHelpers.string(raw["intro"])
        return try Album(
            rawId: id,
            title: title,
            artist: artist,
            intro: intro,
            coverUrl: XmlyIdentifiers.coverUrl(from: raw),
            total: total
        )
    }

    private func trackFromApi(
        _ raw: [String: Any],
        albumId: String = "",
        officialPosition: Int? = nil
    ) -> Track? {
        let id = JSONHelpers.string(raw["trackId"] ?? raw["id"])
        guard !id.isEmpty else { return nil }
        let resolvedAlbum = albumId.isEmpty ? JSONHelpers.string(raw["albumId"] ?? raw["album_id"]) : albumId
        let orderNo = XmlyIdentifiers.xmlyPositive(raw["orderNo"] ?? raw["orderNum"] ?? raw["order_no"])
        let episode = XmlyIdentifiers.xmlyPositive(raw["episode"])
        let duration = JSONHelpers.double(raw["duration"]) ?? 0.0
        let isPaid = JSONHelpers.bool(raw["isPaid"]) ?? JSONHelpers.bool(raw["is_paid"])
        let isAuthorized = JSONHelpers.bool(raw["isAuthorized"])
        let direction = JSONHelpers.signedInt(raw["direction"]) ?? 0
        return try? Track(
            rawId: id,
            title: JSONHelpers.string(raw["title"]),
            artist: JSONHelpers.string(raw["nickname"]),
            album: JSONHelpers.string(raw["albumTitle"] ?? raw["album_title"]),
            albumId: resolvedAlbum,
            duration: duration,
            orderNo: orderNo,
            episode: episode,
            officialPosition: officialPosition,
            isPaid: isPaid,
            isAuthorized: isAuthorized,
            coverUrl: XmlyIdentifiers.coverUrl(from: raw),
            intro: JSONHelpers.string(raw["intro"]),
            direction: direction
        )
    }
}
