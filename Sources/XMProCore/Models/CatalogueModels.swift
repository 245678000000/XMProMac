import Foundation

/// 每次专辑分页拉取的条数（对齐 XMPro 协议常数）
public let xmlyAlbumPageSize = 200

/// 单日听时账本上限（秒）
public let xmlyMaxUsageSeconds = 24 * 60 * 60

/// 支持的音频清晰度优先级（由高到低）
public let xmlyQualities: [String] = ["m4a_128", "m4a_64", "mp3_64", "mp3_32", "m4a_24"]

/// 单集声音元数据
public struct Track: Identifiable, Equatable, Hashable, Codable, Sendable {
    /// 规范形式 `xmly:<id>`
    public let id: String
    /// 纯数字声音 ID
    public let number: String
    public let title: String
    public let artist: String
    public let album: String
    /// 纯数字专辑 ID（缺失时为空字符串）
    public let albumKey: String
    public let duration: Double
    public let orderNo: Int?
    public let episode: Int?
    public let officialPosition: Int?
    public let isPaid: Bool?
    public let isAuthorized: Bool?
    public let coverUrl: String?
    public let intro: String
    /// 专辑播放顺序方向（0 正序 / 1 倒序），供云端历史合并使用
    public let direction: Int

    public init(
        rawId: String,
        title: String = "",
        artist: String = "",
        album: String = "",
        albumId: String = "",
        duration: Double = 0.0,
        orderNo: Int? = nil,
        episode: Int? = nil,
        officialPosition: Int? = nil,
        isPaid: Bool? = nil,
        isAuthorized: Bool? = nil,
        coverUrl: String? = nil,
        intro: String = "",
        direction: Int = 0
    ) throws {
        let normalizedId = try XmlyIdentifiers.xmlyIdentifier(rawId)
        self.number = normalizedId
        self.id = "xmly:\(normalizedId)"
        self.title = title
        self.artist = artist
        self.album = album
        if albumId.isEmpty {
            self.albumKey = ""
        } else {
            self.albumKey = (try? XmlyIdentifiers.xmlyIdentifier(albumId)) ?? ""
        }
        self.duration = duration.isFinite && duration >= 0 ? duration : 0.0
        self.orderNo = orderNo
        self.episode = episode
        self.officialPosition = officialPosition
        self.isPaid = isPaid
        self.isAuthorized = isAuthorized
        self.coverUrl = coverUrl
        self.intro = intro
        self.direction = (direction == 1) ? 1 : 0
    }

    /// 展示序号（优先使用 orderNo，其次 officialPosition / episode）
    public var displayOrder: Int? {
        orderNo ?? officialPosition ?? episode
    }
}

/// 专辑元数据
public struct Album: Identifiable, Equatable, Hashable, Codable, Sendable {
    /// 纯数字专辑 ID
    public let id: String
    public let title: String
    public let artist: String
    public let intro: String
    public let coverUrl: String?
    public let total: Int

    public init(
        rawId: String,
        title: String = "",
        artist: String = "",
        intro: String = "",
        coverUrl: String? = nil,
        total: Int = 0
    ) throws {
        self.id = try XmlyIdentifiers.xmlyIdentifier(rawId)
        self.title = title
        self.artist = artist
        self.intro = intro
        self.coverUrl = coverUrl
        self.total = max(0, total)
    }
}

/// 专辑单页响应
public struct AlbumPage: Equatable, Sendable {
    public let album: Album
    public let tracks: [Track]
    public let page: Int
    public let pageSize: Int
    public let total: Int

    public init(album: Album, tracks: [Track], page: Int, pageSize: Int, total: Int) {
        self.album = album
        self.tracks = tracks
        self.page = page
        self.pageSize = pageSize
        self.total = total
    }
}

/// 搜索单页响应
public struct SearchPage: Equatable, Sendable {
    public let tracks: [Track]
    public let albums: [Album]
    public let page: Int
    public let pageSize: Int
    public let total: Int
    public let kind: String

    public init(
        tracks: [Track] = [],
        albums: [Album] = [],
        page: Int,
        pageSize: Int,
        total: Int,
        kind: String
    ) {
        self.tracks = tracks
        self.albums = albums
        self.page = page
        self.pageSize = pageSize
        self.total = total
        self.kind = kind
    }
}

/// 当前设备的剩余听时额度
public struct Quota: Equatable, Codable, Sendable {
    public let remainingSeconds: Int
    public let newDevice: Bool
    public let checkedAt: Date

    public init(remainingSeconds: Int, newDevice: Bool, checkedAt: Date) {
        self.remainingSeconds = max(0, remainingSeconds)
        self.newDevice = newDevice
        self.checkedAt = checkedAt
    }
}

/// 解密后的可播音频流结果
public struct ResolvedAudio: Equatable, Sendable {
    public let url: String
    public let headers: [String: String]
    public let requiresReward: Bool
    public let track: Track
    public let actualQuality: String
    public let accountIdentity: String

    public init(
        url: String,
        headers: [String: String] = [:],
        requiresReward: Bool,
        track: Track,
        actualQuality: String,
        accountIdentity: String
    ) {
        self.url = url
        self.headers = headers
        self.requiresReward = requiresReward
        self.track = track
        self.actualQuality = actualQuality
        self.accountIdentity = accountIdentity
    }
}

/// 已登录用户的非敏感资料缓存
public struct UserProfile: Equatable, Codable, Sendable {
    public let uid: String
    public let nickname: String
    public let avatarUrl: String?
    public let intro: String
    public let followers: Int?
    public let following: Int?
    public let subscriptions: Int?

    public init(
        uid: String,
        nickname: String = "",
        avatarUrl: String? = nil,
        intro: String = "",
        followers: Int? = nil,
        following: Int? = nil,
        subscriptions: Int? = nil
    ) {
        self.uid = uid
        self.nickname = nickname
        self.avatarUrl = avatarUrl
        self.intro = intro
        self.followers = followers
        self.following = following
        self.subscriptions = subscriptions
    }
}

/// 短信登录成功返回结果
public struct LoginResult: Equatable, Sendable {
    public let credentials: Credentials
    public let nickname: String
    public let avatarUrl: String?
    public let mobile: String

    public init(
        credentials: Credentials,
        nickname: String = "",
        avatarUrl: String? = nil,
        mobile: String = ""
    ) {
        self.credentials = credentials
        self.nickname = nickname
        self.avatarUrl = avatarUrl
        self.mobile = mobile
    }
}

/// 本机记录的专辑最近播放位置（云端仅存最新一条，本地可留最近多条）
public struct PlayPosition: Identifiable, Equatable, Codable, Sendable {
    public var id: String { "\(track.id)_\(atMillis)" }
    public let track: Track
    public let positionSeconds: Double
    public let atMillis: Int64

    public var albumKey: String { track.albumKey }

    public init(track: Track, positionSeconds: Double, atMillis: Int64) {
        self.track = track
        self.positionSeconds = max(0, positionSeconds)
        self.atMillis = atMillis
    }
}
