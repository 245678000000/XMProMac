import Foundation

/// 云端播放历史：拉取合并后的历史列表、同步单条绝对播放进度、删除历史记录
public final class XmlyHistory: @unchecked Sendable {
    private static let material = "23627d1451047b8d257a96af5db359538f081d651df75b4aa169508547208159"

    private let client: XmlyClient
    private let clock: ServerClock

    public init(client: XmlyClient, clock: ServerClock = .shared) {
        self.client = client
        self.clock = clock
    }

    /// 历史接口签名：按键名升序拼接 `k=v&` + 固定盐，仅对 ASCII 大写转小写后做 MD5
    public static func signature(_ params: [String: String]) -> String {
        var text = ""
        for key in params.keys.sorted() {
            text += "\(key)=\(params[key] ?? "")&"
        }
        text += material
        return XmlyCrypto.md5Hex(XmlyCrypto.asciiLowercasedUTF8(text))
    }

    /// 拉取全量历史记录（按最新播放时间倒序，每声音仅保留最新一条）
    public func records() async throws -> [HistoryRecord] {
        let ctx = try validatedContext()
        var items: [String: HistoryRecord] = [:]
        var seenPages = Set<String>()

        for page in 1...50 {
            let response = try await client.request(
                method: "GET",
                origin: XmlyClient.mobileOrigin,
                path: "/nyx/v1/history/query/android",
                query: [
                    "pageId": String(page),
                    "pageSize": "100",
                    "syncPoint": "0",
                    "uid": ctx["uid"] ?? "",
                ]
            )
            let data = try extractData(response)
            guard let rawList = data["listenModels"] as? [[String: Any]],
                  let hasMore = JSONHelpers.bool(data["hasMore"]),
                  rawList.count <= 100 else {
                throw XmlyException(code: "invalid_history", message: "历史分页格式无效")
            }
            if !rawList.isEmpty {
                let fp = fingerprint(rawList)
                guard seenPages.insert(fp).inserted else {
                    throw XmlyException(code: "repeated_page", message: "历史服务返回重复分页")
                }
            }
            for row in rawList {
                guard let record = normalize(row) else { continue }
                if let existing = items[record.track.id], existing.updatedAtMillis >= record.updatedAtMillis {
                    continue
                }
                items[record.track.id] = record
            }
            if !hasMore {
                return items.values.sorted { $0.updatedAtMillis > $1.updatedAtMillis }
            }
            if rawList.isEmpty {
                throw XmlyException(code: "invalid_history", message: "历史分页未返回记录")
            }
        }
        throw XmlyException(code: "history_limit", message: "历史记录超过 5000 条上限")
    }

    /// 仅拉取最新若干条历史记录（用于打开专辑时快速检测续播位置）
    public func newest(limit: Int = 100) async throws -> [HistoryRecord] {
        guard limit > 0 else { return [] }
        let ctx = try validatedContext()
        var items: [String: HistoryRecord] = [:]
        var page = 1

        while items.count < limit && page <= 50 {
            let response = try await client.request(
                method: "GET",
                origin: XmlyClient.mobileOrigin,
                path: "/nyx/v1/history/query/android",
                query: [
                    "pageId": String(page),
                    "pageSize": "100",
                    "syncPoint": "0",
                    "uid": ctx["uid"] ?? "",
                ]
            )
            let data = try extractData(response)
            guard let rawList = data["listenModels"] as? [[String: Any]] else { break }
            for row in rawList {
                guard let record = normalize(row) else { continue }
                if let existing = items[record.track.id], existing.updatedAtMillis >= record.updatedAtMillis {
                    continue
                }
                items[record.track.id] = record
                if items.count >= limit { break }
            }
            if JSONHelpers.bool(data["hasMore"]) != true || rawList.isEmpty { break }
            page += 1
        }
        return items.values.sorted { $0.updatedAtMillis > $1.updatedAtMillis }
    }

    /// 同步单条播放进度到云端（严格保证 direction 为整数，避免服务端 HTTP 500）
    public func sync(
        track: Track,
        positionSeconds: Double,
        startedAtMillis: Int64,
        endedAtMillis: Int64
    ) async throws {
        guard track.id.hasPrefix("xmly:") else {
            throw XmlyException(code: "invalid_history", message: "只能同步喜马拉雅声音", definitive: true)
        }
        var position = positionSeconds
        guard position.isFinite, position >= 0, position <= 2_147_483_647.0 else {
            throw XmlyException(code: "invalid_history", message: "播放进度无效", definitive: true)
        }
        var ended = endedAtMillis
        guard startedAtMillis > 0, startedAtMillis <= ended, ended <= 2_115_354_119_000 else {
            throw XmlyException(code: "invalid_history", message: "收听起止时间无效", definitive: true)
        }
        if track.duration.isFinite && track.duration > 0 {
            position = min(max(position, 0.0), track.duration)
        }
        if ended == startedAtMillis {
            ended = max(clock.nowMillis(), startedAtMillis)
        }
        let album = track.albumKey
        guard !album.isEmpty else {
            throw XmlyException(code: "invalid_history", message: "缺少专辑标识", definitive: true)
        }

        let recordObj: [String: Any] = [
            "endedAt": String(ended),
            "startedAt": String(startedAtMillis),
            "type": "1",
            "itemId": album,
            "childId": track.number,
            "breakSecond": String(Int(position)),
            "direction": Int(track.direction),
        ]
        let arrayData = try JSONSerialization.data(withJSONObject: [recordObj], options: [])
        let mergeRecords = String(data: arrayData, encoding: .utf8) ?? "[]"

        var signParams = try validatedContext()
        signParams["mergeRecords"] = mergeRecords
        let form: [String: String] = [
            "mergeRecords": mergeRecords,
            "signature": Self.signature(signParams),
        ]
        let response = try await client.request(
            method: "POST",
            origin: client.collector,
            path: "/nyx/v1/history/merge/android",
            form: form,
            readOnly: true
        )
        let data = try extractData(response)
        let syncPoint = JSONHelpers.int64(data["syncPoint"]) ?? -1
        guard syncPoint >= 0 else {
            throw XmlyException(code: "history_unconfirmed", message: "未能确认历史进度同步")
        }
    }

    /// 从云端删除一条历史记录（写操作不重放）
    public func delete(record: HistoryRecord) async throws {
        let ctx = try validatedContext()
        let album = record.track.albumKey
        guard !album.isEmpty else {
            throw XmlyException(code: "invalid_history", message: "缺少专辑标识", definitive: true)
        }
        let params: [String: String] = [
            "itemId": album,
            "childId": record.track.number,
            "type": "1",
            "deleteTime": String(clock.nowMillis()),
        ]
        var signParams = ctx
        for (k, v) in params { signParams[k] = v }
        var form = params
        form["signature"] = Self.signature(signParams)
        _ = try await client.request(
            method: "POST",
            origin: client.collector,
            path: "/nyx/v1/history/delete/android",
            form: form,
            readOnly: false
        )
    }

    // MARK: - 内部辅助

    private func validatedContext() throws -> [String: String] {
        let ctx = try client.context()
        let uid = ctx["uid"] ?? ""
        guard !uid.isEmpty, uid.allSatisfy(\.isNumber), !uid.hasPrefix("0") else {
            throw XmlyException(code: "auth_required", message: "历史同步需要有效的极速版登录态", definitive: true)
        }
        return ctx
    }

    private func extractData(_ response: [String: Any]) throws -> [String: Any] {
        if let dict = response["data"] as? [String: Any] {
            return dict
        }
        if let str = response["data"] as? String,
           let d = str.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            return parsed
        }
        throw XmlyException(code: "invalid_history", message: "历史记录格式无效")
    }

    private func normalize(_ raw: [String: Any]) -> HistoryRecord? {
        let type = JSONHelpers.int64(raw["type"]) ?? 0
        guard type == 1 || type == 9 else { return nil }
        guard (JSONHelpers.int64(raw["deleteTime"]) ?? 0) <= 0 else { return nil }

        guard let trackId = try? XmlyIdentifiers.xmlyIdentifier(JSONHelpers.string(raw["childId"])),
              let albumId = try? XmlyIdentifiers.xmlyIdentifier(JSONHelpers.string(raw["itemId"])) else {
            return nil
        }
        let duration = min(max(JSONHelpers.int64(raw["length"]) ?? 0, 0), 2_147_483_647)
        var position = Double(min(max(JSONHelpers.int64(raw["breakSecond"]) ?? 0, 0), 2_147_483_647))
        if duration > 0 {
            position = min(max(position, 0.0), Double(duration))
        }
        let coverMap: [String: Any] = ["cover_url": JSONHelpers.string(raw["itemCoverUrl"])]
        guard let track = try? Track(
            rawId: trackId,
            title: JSONHelpers.string(raw["childTitle"]),
            album: JSONHelpers.string(raw["itemTitle"]),
            albumId: albumId,
            duration: Double(duration),
            coverUrl: XmlyIdentifiers.coverUrl(from: coverMap)
        ) else {
            return nil
        }
        let updatedAt = min(max(JSONHelpers.int64(raw["endedAt"]) ?? 0, 0), 2_115_354_119_000)
        return HistoryRecord(track: track, positionSeconds: position, updatedAtMillis: updatedAt)
    }

    private func fingerprint(_ rows: [[String: Any]]) -> String {
        let ids = rows.map { "\(JSONHelpers.string($0["childId"])):\(JSONHelpers.string($0["endedAt"]))" }
        return ids.joined(separator: "|")
    }
}
