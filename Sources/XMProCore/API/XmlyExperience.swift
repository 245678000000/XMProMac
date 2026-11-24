import Foundation

/// 首页频道发现、订阅、收藏、听更新与当前账号资料接口
public final class XmlyExperience: @unchecked Sendable {
    private let client: XmlyClient
    private let invalidError = XmlyException(code: "invalid_home", message: "首页数据无效", definitive: true)

    public init(client: XmlyClient) {
        self.client = client
    }

    /// 获取顶部首页频道列表
    public func channels() async throws -> [HomeChannel] {
        let data = try await get(
            path: "/lite-mobile/index/v1/subPages/\(stamp())",
            query: [
                "latestTheaterViewTimestamp": "0",
                "theaterDefaultMark": "0",
            ]
        )
        var seen = Set<Int>()
        var result: [HomeChannel] = []
        for row in try extractRows(data["subPages"]) {
            guard let id = JSONHelpers.int(row["pageId"]), id > 0 else { throw invalidError }
            let title = JSONHelpers.string(row["title"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, seen.insert(id).inserted else { throw invalidError }
            result.append(HomeChannel(pageId: id, title: title))
        }
        return result
    }

    /// 加载指定频道的内容模块与二级分类标签
    public func home(pageId: Int, tabId: Int? = nil) async throws -> HomeContent {
        guard pageId > 0 else {
            throw XmlyException(code: "invalid_page", message: "频道无效", definitive: true)
        }
        var query: [String: String] = ["pageId": String(pageId)]
        if let tabId { query["tabId"] = String(tabId) }

        let data = try await get(path: "/lite-mobile/index/v1/modules/\(stamp())", query: query)
        guard let modules = (data["modules"] as? [String: Any])?["list"] else { throw invalidError }

        var sections: [HomeSection] = []
        var tabs: [HomeTab] = []
        var tabIds = Set<Int>()

        for rawModule in try extractRows(modules) {
            let code = JSONHelpers.string(rawModule["moduleCode"])
            switch code {
            case "pageTab":
                for rawTab in try extractRows(rawModule["list"]) {
                    guard let id = JSONHelpers.int(rawTab["tabId"]), id > 0 else { throw invalidError }
                    let title = JSONHelpers.string(rawTab["title"]).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty, tabIds.insert(id).inserted else { throw invalidError }
                    tabs.append(HomeTab(tabId: id, title: title))
                }
            case "rankingLists":
                for rawRanking in try extractRows(rawModule["list"]) {
                    guard JSONHelpers.bool(rawRanking["isDefault"]) == true else { continue }
                    let items = try extractRows(rawRanking["list"])
                    if !items.isEmpty {
                        sections.append(try buildSection(
                            title: JSONHelpers.string(rawRanking["rankingListName"]),
                            rows: items,
                            ranking: true
                        ))
                    }
                }
            case "feedStream":
                var albums: [[String: Any]] = []
                for rawItem in try extractRows(rawModule["list"]) {
                    guard JSONHelpers.string(rawItem["itemType"]) == "ALBUM" else { continue }
                    guard let item = rawItem["item"] as? [String: Any] else { throw invalidError }
                    albums.append(item)
                }
                if !albums.isEmpty {
                    sections.append(try buildSection(
                        title: JSONHelpers.string(rawModule["title"]),
                        rows: albums,
                        ranking: false
                    ))
                }
            case "contentPool":
                let items = try extractRows(rawModule["list"])
                if !items.isEmpty {
                    sections.append(try buildSection(
                        title: JSONHelpers.string(rawModule["title"]),
                        rows: items,
                        ranking: false
                    ))
                }
            default:
                break
            }
        }
        return HomeContent(sections: sections, tabs: tabs)
    }

    /// 订阅专辑列表（含最新集与未读计数）
    public func subscriptions(page: Int = 1, pageSize: Int = 30) async throws -> SubscriptionPage {
        try requireAccount()
        try validatePaging(page: page, size: pageSize)
        let data = try await get(
            path: "/fsubscribe-web/subscribe/comprehensive/rank/\(stamp())",
            query: ["pageId": String(page), "sign": "2", "size": String(pageSize)]
        )
        var seen = Set<String>()
        var items: [SubscriptionItem] = []
        for row in try extractRows(data["albumResults"]).prefix(pageSize) {
            guard !JSONHelpers.string(row["albumId"]).isEmpty else { continue }
            guard let album = try? parseSubscriptionAlbum(row), seen.insert(album.id).inserted else { continue }
            let updatedAt = (try? parseTimestamp(row["lastUpdateAt"] ?? 0)) ?? 0
            items.append(SubscriptionItem(
                album: album,
                latestTitle: JSONHelpers.string(row["trackTitle"]),
                unreadCount: JSONHelpers.int(row["unreadNum"]) ?? 0,
                updatedAtMillis: updatedAt
            ))
        }
        let hasMore = (JSONHelpers.bool(data["hasMore"]) ?? (items.count >= pageSize)) && !items.isEmpty
        return SubscriptionPage(items: items, hasMore: hasMore)
    }

    /// 收藏声音列表
    public func favorites(page: Int = 1, pageSize: Int = 30) async throws -> FavoritePage {
        try requireAccount()
        try validatePaging(page: page, size: pageSize)
        let data = try await get(
            path: "/lite-mobile/like/v1/user-likes",
            query: ["pageId": String(page), "pageSize": String(pageSize)]
        )
        let maxPage = JSONHelpers.int(data["maxPageId"]) ?? 0
        var seen = Set<String>()
        var items: [Track] = []
        for row in try extractRows(data["dataList"]).prefix(pageSize) {
            guard JSONHelpers.int(row["resourceType"]) == 1 else { continue }
            let tid = JSONHelpers.string(row["trackId"]).isEmpty
                ? JSONHelpers.string(row["id"])
                : JSONHelpers.string(row["trackId"])
            guard !tid.isEmpty, let track = try? parseTrack(row), !track.albumKey.isEmpty else { continue }
            guard seen.insert(track.id).inserted else {
                throw XmlyException(code: "repeated_page", message: "收藏列表重复，请刷新后重试")
            }
            items.append(track)
        }
        let hasMore = maxPage > 0 && page < maxPage && !items.isEmpty
        return FavoritePage(items: items, hasMore: hasMore)
    }

    /// 听更新动态流（按 timeline 游标向后翻页）
    public func updates(before: Int64? = nil, pageSize: Int = 30) async throws -> UpdatePage {
        try requireAccount()
        try validatePaging(page: 1, size: pageSize)
        if let before, before <= 0 || before > 2_115_354_119_000 {
            throw invalidError
        }
        var query: [String: String] = ["sign": "2", "size": String(pageSize)]
        if let before { query["timeline"] = String(before) }

        let data = try await get(path: "/track-feed/v1/track-feed/dynamic/ts-\(stamp())", query: query)
        var seen = Set<String>()
        var cursor: Int64?
        var items: [UpdateItem] = []

        for row in try extractRows(data["trackResults"]).prefix(pageSize) {
            let tid = JSONHelpers.string(row["trackId"]).isEmpty
                ? JSONHelpers.string(row["id"])
                : JSONHelpers.string(row["trackId"])
            guard !tid.isEmpty, let timeline = parseBoundedInt64(row["timeline"]) else { continue }
            guard let track = try? parseTrack(row) else { continue }
            guard seen.insert(track.id).inserted else {
                throw XmlyException(code: "repeated_page", message: "更新列表重复，请刷新后重试")
            }
            cursor = timeline
            let created = parseBoundedInt64(row["createdAt"]) ?? timeline
            items.append(UpdateItem(track: track, publishedAtMillis: created))
        }
        guard let hasMoreFlag = JSONHelpers.bool(data["hasMore"]) else { throw invalidError }
        if let before, let next = cursor, next >= before {
            throw XmlyException(code: "repeated_page", message: "暂时无法读取更早的更新，已保留当前列表")
        }
        return UpdatePage(
            items: items,
            hasMore: hasMoreFlag && (cursor ?? 0) > 0,
            nextTimeline: cursor
        )
    }

    /// 订阅或取消订阅专辑（使用主站接口，移动端接口恒返 ret=791）
    public func setSubscribed(albumId: String, subscribed: Bool) async throws {
        try requireAccount()
        let id = try XmlyIdentifiers.xmlyIdentifier(albumId)
        let path = subscribed
            ? "/revision/subscription/setSubscriptionAlbum"
            : "/revision/subscription/cancelSubscriptionAlbum"
        let payload = try await client.request(
            method: "POST",
            origin: XmlyClient.webOrigin,
            path: path,
            form: ["albumId": id],
            readOnly: false
        )
        let ret = JSONHelpers.int(payload["ret"])
        guard ret == 200 || ret == 0 else { throw invalidError }
    }

    /// 收藏或取消收藏单集声音
    public func setFavorite(track: Track, favorite: Bool) async throws {
        try requireAccount()
        let id = try XmlyIdentifiers.xmlyIdentifier(track.id)
        var albumKey = track.albumKey
        if albumKey.isEmpty {
            albumKey = try await client.track(number: id).albumKey
        }
        guard !albumKey.isEmpty else {
            throw XmlyException(code: "missing_album", message: "缺少专辑标识", definitive: true)
        }
        let payload = try await client.request(
            method: "POST",
            origin: XmlyClient.mobileOrigin,
            path: favorite ? "/lite-mobile/like/v1/like" : "/lite-mobile/like/v1/dislike",
            form: ["resourceId": id, "albumId": albumKey, "resourceType": "1"],
            readOnly: false
        )
        guard JSONHelpers.int(payload["ret"]) == 0 else { throw invalidError }
    }

    /// 读取当前已登录用户资料
    public func profile() async throws -> UserProfile {
        try requireAccount()
        guard let uid = try client.context()["uid"] else { throw invalidError }
        let payload = try await fetchProfilePayload(uid: uid)
        let nickname = JSONHelpers.findFirstString(in: payload, keys: ["nickname", "userName", "name", "nickName"]) ?? ""
        let avatar = JSONHelpers.findFirstString(in: payload, keys: ["avatar", "avatarUrl", "logoPic", "smallLogo", "cover"])
        let mobile = JSONHelpers.findFirstString(in: payload, keys: ["mobile", "phone", "mobilePhone"]) ?? ""
        if nickname.isEmpty && avatar == nil && mobile.isEmpty {
            throw XmlyException(code: "profile_unavailable", message: "账号资料不可用", definitive: true)
        }
        let intro = JSONHelpers.findFirstString(in: payload, keys: ["personalSignature", "intro", "description"]) ?? ""
        return UserProfile(
            uid: uid,
            nickname: nickname,
            avatarUrl: XmlyIdentifiers.cdnUrl(avatar),
            intro: intro
        )
    }

    // MARK: - 内部解析辅助

    private func fetchProfilePayload(uid: String) async throws -> [String: Any] {
        var lastError: Error?
        do {
            let webPayload = try await client.request(
                method: "GET",
                origin: XmlyHttp.searchOrigin,
                path: "/revision/my/getCurrentUserInfo"
            )
            if webPayload["data"] is [String: Any] || webPayload["uid"] != nil {
                return webPayload
            }
        } catch {
            lastError = error
        }

        do {
            let mobilePayload = try await client.request(
                method: "GET",
                origin: XmlyClient.mobileOrigin,
                path: "/mobile-user/user/detail",
                query: ["uid": uid, "device": "android"]
            )
            if mobilePayload["data"] is [String: Any] || mobilePayload["uid"] != nil {
                return mobilePayload
            }
        } catch {
            lastError = error
        }

        if let xmly = lastError as? XmlyException { throw xmly }
        throw XmlyException(code: "profile_unavailable", message: "账号资料不可用", definitive: true)
    }

    private func buildSection(title: String, rows: [[String: Any]], ranking: Bool) throws -> HomeSection {
        var albums: [Album] = []
        var stats: [String: HomeAlbumStats] = [:]
        var ids = Set<String>()
        for row in rows {
            guard let album = try? parseHomeAlbum(row), ids.insert(album.id).inserted else { continue }
            albums.append(album)
            let score = JSONHelpers.double(row["albumScore"]).flatMap { ($0.isFinite && (0...10).contains($0)) ? $0 : nil }
            stats[album.id] = HomeAlbumStats(
                score: score,
                playCount: JSONHelpers.int(row["playCount"]),
                subscribeCount: JSONHelpers.int(row["subscribeCount"]),
                finished: JSONHelpers.bool(row["isFinished"]) == true
            )
        }
        let finalTitle = title.isEmpty ? (ranking ? "排行榜" : "推荐专辑") : title
        return HomeSection(title: finalTitle, albums: albums, isRanking: ranking, stats: stats)
    }

    private func parseHomeAlbum(_ row: [String: Any]) throws -> Album {
        let albumId = JSONHelpers.string(row["albumId"])
        guard !albumId.isEmpty else { throw invalidError }
        let id = try XmlyIdentifiers.xmlyIdentifier(albumId)
        let coverMap: [String: Any] = [
            "coverLarge": JSONHelpers.string(row["coverLarge"]),
            "coverMiddle": JSONHelpers.string(row["coverMiddle"]),
            "coverSmall": JSONHelpers.string(row["coverSmall"]),
        ]
        return try Album(
            rawId: id,
            title: JSONHelpers.string(row["albumTitle"]),
            artist: JSONHelpers.string(row["nickname"]),
            intro: JSONHelpers.string(row["albumIntro"]),
            coverUrl: XmlyIdentifiers.coverUrl(from: coverMap),
            total: JSONHelpers.int(row["trackCount"]) ?? 0
        )
    }

    private func parseSubscriptionAlbum(_ row: [String: Any]) throws -> Album {
        let albumId = JSONHelpers.string(row["albumId"])
        guard !albumId.isEmpty else { throw invalidError }
        let coverMap: [String: Any] = [
            "coverLarge": JSONHelpers.string(row["coverLarge"]),
            "coverMiddle": JSONHelpers.string(row["coverMiddle"]),
            "coverSmall": JSONHelpers.string(row["coverSmall"]),
            "cover_url": JSONHelpers.string(row["albumCover"]),
        ]
        return try Album(
            rawId: XmlyIdentifiers.xmlyIdentifier(albumId),
            title: JSONHelpers.string(row["albumTitle"]),
            artist: JSONHelpers.string(row["nickname"]),
            intro: JSONHelpers.string(row["albumIntro"]),
            coverUrl: XmlyIdentifiers.coverUrl(from: coverMap),
            total: JSONHelpers.int(row["trackCount"]) ?? 0
        )
    }

    private func parseTrack(_ row: [String: Any]) throws -> Track {
        let id = JSONHelpers.string(row["trackId"]).isEmpty
            ? JSONHelpers.string(row["id"])
            : JSONHelpers.string(row["trackId"])
        guard !id.isEmpty else { throw invalidError }
        let albumId = JSONHelpers.string(row["albumId"]).isEmpty
            ? JSONHelpers.string(row["album_id"])
            : JSONHelpers.string(row["albumId"])
        let coverMap: [String: Any] = [
            "coverLarge": JSONHelpers.string(row["coverLarge"]),
            "coverMiddle": JSONHelpers.string(row["coverMiddle"]),
            "coverSmall": JSONHelpers.string(row["coverSmall"]),
            "cover_url": JSONHelpers.string(row["cover"]),
        ]
        return try Track(
            rawId: id,
            title: JSONHelpers.string(row["title"]),
            artist: JSONHelpers.string(row["nickname"]),
            album: JSONHelpers.string(row["albumTitle"]),
            albumId: albumId,
            duration: JSONHelpers.double(row["duration"]) ?? 0.0,
            isPaid: JSONHelpers.bool(row["isPaid"]) ?? JSONHelpers.bool(row["paid"]),
            isAuthorized: JSONHelpers.bool(row["isAuthorized"]) ?? JSONHelpers.bool(row["authorized"]),
            coverUrl: XmlyIdentifiers.coverUrl(from: coverMap)
        )
    }

    private func get(path: String, query: [String: String]) async throws -> [String: Any] {
        let payload: [String: Any]
        if client.credentials != nil {
            payload = try await client.request(method: "GET", origin: client.mobile, path: path, query: query)
        } else {
            payload = try await client.getMobile(path: path, query: query)
        }
        guard let data = payload["data"] as? [String: Any] else { throw invalidError }
        return data
    }

    private func requireAccount() throws {
        if client.credentials == nil {
            throw XmlyException(code: "login_required", message: "登录后使用订阅、收藏和更新", definitive: true)
        }
    }

    private func validatePaging(page: Int, size: Int) throws {
        guard (1...10000).contains(page), (1...50).contains(size) else {
            throw XmlyException(code: "invalid_page", message: "页码范围为 1..10000，每页 1..50", definitive: true)
        }
    }

    private func extractRows(_ value: Any?) throws -> [[String: Any]] {
        let array: [Any]
        if let arr = value as? [Any] {
            array = arr
        } else if let dict = value as? [String: Any], let inner = dict["list"] as? [Any] {
            array = inner
        } else {
            return []
        }
        guard array.count <= 500 else { throw invalidError }
        return array.compactMap { $0 as? [String: Any] }
    }

    private func parseBoundedInt64(_ value: Any?) -> Int64? {
        guard let n = JSONHelpers.int64(value), n >= 0, n <= 2_115_354_119_000 else { return nil }
        return n
    }

    private func parseTimestamp(_ value: Any?) throws -> Int64 {
        guard let n = parseBoundedInt64(value) else { throw invalidError }
        return n
    }

    private func stamp() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
