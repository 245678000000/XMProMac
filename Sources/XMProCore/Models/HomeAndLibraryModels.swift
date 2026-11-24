import Foundation

/// 首页频道标签（如“推荐”、“小说”）
public struct HomeChannel: Identifiable, Equatable, Hashable, Codable, Sendable {
    public var id: Int { pageId }
    public let pageId: Int
    public let title: String

    public init(pageId: Int, title: String) {
        self.pageId = pageId
        self.title = title
    }
}

/// 频道内二级分类标签
public struct HomeTab: Identifiable, Equatable, Hashable, Sendable {
    public var id: Int { tabId }
    public let tabId: Int
    public let title: String

    public init(tabId: Int, title: String) {
        self.tabId = tabId
        self.title = title
    }
}

/// 首页专辑统计信息
public struct HomeAlbumStats: Equatable, Sendable {
    public let score: Double?
    public let playCount: Int?
    public let subscribeCount: Int?
    public let finished: Bool

    public init(
        score: Double? = nil,
        playCount: Int? = nil,
        subscribeCount: Int? = nil,
        finished: Bool = false
    ) {
        self.score = score
        self.playCount = playCount
        self.subscribeCount = subscribeCount
        self.finished = finished
    }
}

/// 首页模块分组（排行榜 / 推荐流）
public struct HomeSection: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let albums: [Album]
    public let isRanking: Bool
    public let stats: [String: HomeAlbumStats]

    public init(
        id: String = UUID().uuidString,
        title: String,
        albums: [Album],
        isRanking: Bool = false,
        stats: [String: HomeAlbumStats] = [:]
    ) {
        self.id = id
        self.title = title
        self.albums = albums
        self.isRanking = isRanking
        self.stats = stats
    }
}

/// 首页加载结果
public struct HomeContent: Equatable, Sendable {
    public let sections: [HomeSection]
    public let tabs: [HomeTab]

    public init(sections: [HomeSection], tabs: [HomeTab] = []) {
        self.sections = sections
        self.tabs = tabs
    }
}

/// 订阅专辑条目
public struct SubscriptionItem: Identifiable, Equatable, Sendable {
    public var id: String { album.id }
    public let album: Album
    public let latestTitle: String
    public let unreadCount: Int
    public let updatedAtMillis: Int64

    public init(album: Album, latestTitle: String, unreadCount: Int, updatedAtMillis: Int64) {
        self.album = album
        self.latestTitle = latestTitle
        self.unreadCount = unreadCount
        self.updatedAtMillis = updatedAtMillis
    }
}

public struct SubscriptionPage: Equatable, Sendable {
    public let items: [SubscriptionItem]
    public let hasMore: Bool

    public init(items: [SubscriptionItem], hasMore: Bool) {
        self.items = items
        self.hasMore = hasMore
    }
}

public struct FavoritePage: Equatable, Sendable {
    public let items: [Track]
    public let hasMore: Bool

    public init(items: [Track], hasMore: Bool) {
        self.items = items
        self.hasMore = hasMore
    }
}

/// 听更新单条动态
public struct UpdateItem: Identifiable, Equatable, Sendable {
    public var id: String { track.id }
    public let track: Track
    public let publishedAtMillis: Int64

    public init(track: Track, publishedAtMillis: Int64) {
        self.track = track
        self.publishedAtMillis = publishedAtMillis
    }
}

public struct UpdatePage: Equatable, Sendable {
    public let items: [UpdateItem]
    public let hasMore: Bool
    public let nextTimeline: Int64?

    public init(items: [UpdateItem], hasMore: Bool, nextTimeline: Int64?) {
        self.items = items
        self.hasMore = hasMore
        self.nextTimeline = nextTimeline
    }
}

/// 云端单条播放历史记录
public struct HistoryRecord: Identifiable, Equatable, Sendable {
    public var id: String { track.id }
    public let track: Track
    public let positionSeconds: Double
    public let updatedAtMillis: Int64

    public init(track: Track, positionSeconds: Double, updatedAtMillis: Int64) {
        self.track = track
        self.positionSeconds = positionSeconds
        self.updatedAtMillis = updatedAtMillis
    }
}

/// 听时福利档位
public struct RewardTier: Identifiable, Equatable, Sendable {
    public var id: String { "\(index)_\(seconds)" }
    public let index: Int
    public let seconds: Int
    public let label: String
    public let status: Int
    public let receiveTimeMillis: Int64

    public init(index: Int, seconds: Int, label: String, status: Int, receiveTimeMillis: Int64) {
        self.index = index
        self.seconds = seconds
        self.label = label
        self.status = status
        self.receiveTimeMillis = receiveTimeMillis
    }
}

/// 音质显示标签映射
public enum QualityLabel {
    public static func title(for quality: String) -> String {
        switch quality.lowercased() {
        case "auto": return "自动（最高可用）"
        case "m4a_128": return "高清 M4A 128k"
        case "m4a_64": return "标准 M4A 64k"
        case "mp3_64": return "标准 MP3 64k"
        case "mp3_32": return "流畅 MP3 32k"
        case "m4a_24": return "省流 M4A 24k"
        default: return quality.isEmpty ? "自动" : quality
        }
    }

    public static func shortBadge(for quality: String) -> String {
        switch quality.lowercased() {
        case "m4a_128": return "HD 128K"
        case "m4a_64": return "M4A 64K"
        case "mp3_64": return "MP3 64K"
        case "mp3_32": return "MP3 32K"
        case "m4a_24": return "24K"
        default: return quality.uppercased()
        }
    }
}
