import Foundation
import Observation
import SwiftUI
import XMProCore

/// 侧边栏一级导航目标
public enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case discover = "发现"
    case updates = "听更新"
    case subscriptions = "订阅"
    case history = "历史"
    case favorites = "收藏"
    case account = "账号与听时"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .discover: return "sparkles"
        case .updates: return "dot.radiowaves.left.and.right"
        case .subscriptions: return "square.stack.fill"
        case .history: return "clock.arrow.circlepath"
        case .favorites: return "heart.fill"
        case .account: return "person.crop.circle"
        }
    }
}

/// 专辑 100 集分段描述符
public struct EpisodeSegment: Identifiable, Equatable, Hashable {
    public let start: Int
    public let end: Int

    public var id: String { "\(start)-\(end)" }
    public var label: String { "\(start)-\(end)" }

    public static func makeSegments(total: Int, chunkSize: Int = 100) -> [EpisodeSegment] {
        guard total > 0 else { return [] }
        var list: [EpisodeSegment] = []
        var s = 1
        while s <= total {
            let e = min(s + chunkSize - 1, total)
            list.append(EpisodeSegment(start: s, end: e))
            s = e + 1
        }
        return list
    }
}

/// 睡眠定时预设
public enum SleepTimerOption: Equatable {
    case off
    case endOfTrack
    case minutes(Int)

    public var label: String {
        switch self {
        case .off: return "关闭"
        case .endOfTrack: return "播完本集"
        case .minutes(let m): return "\(m) 分钟"
        }
    }
}

/// 全局应用与播放状态控制器（主线程隔离，播放秒表拆至 PlaybackClock 避免全屏重绘）
@Observable
@MainActor
public final class AppStore {
    public let storage = AppStorage()
    public let engine = AudioPlayerEngine()
    public let nowPlaying = NowPlayingBridge()
    public var clock: PlaybackClock { engine.clock }

    // MARK: - 导航与 UI 浮层状态
    public var selectedSection: SidebarSection = .discover
    public var showingSearchResults: Bool = false
    public var openedAlbumId: String? = nil
    public var showPlayerDrawer: Bool = false
    public var showLoginSheet: Bool = false
    public var toastMessage: String? = nil
    public var ambientColor: Color = Color.accentColor

    // MARK: - 账号与听时状态
    public private(set) var credentials: Credentials? = nil
    public var profile: UserProfile? = nil
    public var quota: Quota? = nil
    public var rewardTiers: [RewardTier] = []
    public var rewardStatusNote: String = ""
    public var accountBusy: Bool = false
    public var rewardsBusy: Bool = false
    public var signedIn: Bool { credentials != nil }

    // MARK: - 偏好设置
    public var preferences: AppPreferences {
        didSet {
            storage.savePreferences(preferences)
            engine.rate = preferences.speed
            engine.volume = preferences.volume
        }
    }

    // MARK: - 发现页状态
    public var channels: [HomeChannel] = []
    public var selectedChannelId: Int? = nil
    public var homeTabs: [HomeTab] = []
    public var selectedTabId: Int? = nil
    public var homeSections: [HomeSection] = []
    public var homeLoading: Bool = false
    public var homeError: String? = nil

    // MARK: - 搜索状态
    public var searchQuery: String = ""
    public var searchKind: String = "album" // "album" | "track"
    public var searchAlbums: [Album] = []
    public var searchTracks: [Track] = []
    public var searchTotal: Int = 0
    public var searchPage: Int = 0
    public var searchLoading: Bool = false
    public var searchLoadingMore: Bool = false
    public var searchError: String? = nil
    public var canLoadMoreSearch: Bool {
        let count = searchKind == "album" ? searchAlbums.count : searchTracks.count
        return count > 0 && count < searchTotal
    }

    // MARK: - 专辑详情与 100 集分段
    public var currentAlbumPage: AlbumPage? = nil
    public var albumAscending: Bool = true
    public var albumSelectedSegment: EpisodeSegment? = nil
    public var albumLoading: Bool = false
    public var albumSegmentBusy: Bool = false
    public var albumError: String? = nil
    public var albumResumeRecord: HistoryRecord? = nil
    public var albumLocalPositions: [String: [PlayPosition]] = [:]

    // MARK: - 书单四栏（听更新 / 订阅 / 历史 / 收藏）
    public var updates: [UpdateItem] = []
    public var updatesHasMore: Bool = false
    public var updatesNextTimeline: Int64? = nil

    public var subscriptions: [SubscriptionItem] = []
    public var subscriptionsHasMore: Bool = false
    public var subscriptionsPage: Int = 0
    public var subscribedAlbumIds: Set<String> = []

    public var historyRecords: [HistoryRecord] = []

    public var favorites: [Track] = []
    public var favoritesHasMore: Bool = false
    public var favoritesPage: Int = 0
    public var favoriteTrackIds: Set<String> = []

    public var libraryLoading: Bool = false
    public var libraryError: String? = nil

    // MARK: - 播放状态与队列
    public var currentTrack: Track? = nil
    public var isPlaying: Bool = false
    public var isBuffering: Bool = false
    public var isResolving: Bool = false
    public var playingQuality: String = ""
    public var queueAll: [Track] = []
    public var queue: [Track] = []
    public var queueIndex: Int = 0
    public var queueSegment: EpisodeSegment? = nil

    // MARK: - 睡眠定时
    public var sleepTimerOption: SleepTimerOption = .off
    public var sleepDeadline: Date? = nil
    public var sleepRemainingSeconds: Int = 0

    // MARK: - 私有协议客户端与防竞态状态
    private let http = XmlyHttp()
    private var client: XmlyClient
    public let loginClient: XmlyLogin

    private var playRequestId: Int = 0
    private var sessionStartedAtMillis: Int64 = 0
    private var sessionRequiresReward: Bool = false
    private var unbilledRewardSeconds: Double = 0
    private var lastTickAt: Date = Date()
    private var secondsSinceProgressSync: Double = 0
    private var activeSmartTrim: SmartSilenceAnalyzer.TrimPoints? = nil
    private var smartTrimTask: Task<Void, Never>? = nil
    private var recoverTrackId: String? = nil
    private var recoverAttempts: Int = 0
    private var tickerTask: Task<Void, Never>? = nil
    private var autoClaimTask: Task<Void, Never>? = nil
    private var toastTask: Task<Void, Never>? = nil
    private var homeCache: [String: HomeContent] = [:]

    public init() {
        let loadedPrefs = storage.loadPreferences()
        let loadedCreds = storage.loadCredentials()
        let loadedProfile = storage.loadProfile()
        let loadedPositions = storage.loadPositions()

        self.preferences = loadedPrefs
        self.credentials = loadedCreds
        self.profile = loadedProfile
        self.albumLocalPositions = loadedPositions
        self.client = XmlyClient(http: http, credentials: loadedCreds)
        self.loginClient = XmlyLogin(deviceOverride: loadedPrefs.installDeviceId)

        engine.rate = loadedPrefs.speed
        engine.volume = loadedPrefs.volume

        wirePlayerCallbacks()
        wireRemoteCommands()
        startBackgroundLoops()
    }

    /// 应用启动后的首屏数据初始化
    public func bootstrap() {
        Task {
            await loadHome()
            if signedIn {
                await refreshAccountSummary()
                await refreshLibrary()
            }
        }
    }

    // MARK: - 通知轻提示

    public func showToast(_ text: String) {
        toastMessage = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }

    // MARK: - 发现与首页频道

    public func loadHome(force: Bool = false) async {
        if !force && !channels.isEmpty && !homeSections.isEmpty { return }
        homeLoading = true
        homeError = nil
        do {
            let exp = XmlyExperience(client: client)
            let fetchedChannels = try await exp.channels()
            guard !fetchedChannels.isEmpty else {
                throw XmlyException(code: "invalid_home", message: "首页频道为空")
            }
            channels = fetchedChannels
            let targetChannel = selectedChannelId.flatMap { id in
                fetchedChannels.contains { $0.pageId == id } ? id : nil
            } ?? fetchedChannels.first!.pageId
            selectedChannelId = targetChannel
            await selectChannel(targetChannel, tabId: nil, force: force)
        } catch {
            homeLoading = false
            homeError = describe(error)
        }
    }

    public func selectChannel(_ pageId: Int, tabId: Int? = nil, force: Bool = false) async {
        selectedChannelId = pageId
        selectedTabId = tabId
        let cacheKey = "\(pageId)_\(tabId ?? 0)"
        if !force, let cached = homeCache[cacheKey] {
            homeTabs = cached.tabs.isEmpty ? homeTabs : cached.tabs
            homeSections = cached.sections
            homeLoading = false
            homeError = nil
            return
        }
        homeLoading = true
        homeError = nil
        do {
            let exp = XmlyExperience(client: client)
            let content = try await exp.home(pageId: pageId, tabId: tabId)
            homeCache[cacheKey] = content
            if tabId == nil {
                homeTabs = content.tabs
            }
            homeSections = content.sections
            homeLoading = false
        } catch {
            homeLoading = false
            homeError = describe(error)
        }
    }

    // MARK: - 搜索

    public func performSearch(reset: Bool = true) async {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showingSearchResults = false
            return
        }
        showingSearchResults = true
        openedAlbumId = nil
        if reset {
            searchLoading = true
            searchError = nil
            searchPage = 0
            searchAlbums = []
            searchTracks = []
            searchTotal = 0
        } else {
            guard !searchLoadingMore && canLoadMoreSearch else { return }
            searchLoadingMore = true
        }

        let targetPage = reset ? 1 : (searchPage + 1)
        do {
            let page = try await client.search(query: trimmed, kind: searchKind, page: targetPage, pageSize: 24)
            searchPage = page.page
            searchTotal = page.total
            if reset {
                searchAlbums = page.albums
                searchTracks = page.tracks
            } else {
                let existingAlbumIds = Set(searchAlbums.map(\.id))
                searchAlbums.append(contentsOf: page.albums.filter { !existingAlbumIds.contains($0.id) })
                let existingTrackIds = Set(searchTracks.map(\.id))
                searchTracks.append(contentsOf: page.tracks.filter { !existingTrackIds.contains($0.id) })
            }
            searchLoading = false
            searchLoadingMore = false
        } catch {
            searchLoading = false
            searchLoadingMore = false
            searchError = describe(error)
        }
    }

    public func clearSearch() {
        searchQuery = ""
        showingSearchResults = false
        searchError = nil
    }

    // MARK: - 专辑详情与 100 集分段

    public var albumSegments: [EpisodeSegment] {
        guard let page = currentAlbumPage else { return [] }
        let total = max(page.total, page.tracks.count)
        return EpisodeSegment.makeSegments(total: total, chunkSize: 100)
    }

    /// 当前专辑页面在所选 100 集分段下展示的剧集列表
    public var displayedAlbumTracks: [Track] {
        guard let page = currentAlbumPage else { return [] }
        guard let seg = albumSelectedSegment else { return page.tracks }
        return page.tracks.enumerated().compactMap { index, track in
            let ordinal = track.displayOrder ?? (index + 1)
            return (seg.start...seg.end).contains(ordinal) ? track : nil
        }
    }

    /// 专辑最近续播点（在云端历史与本机记忆间取更新者）
    public var effectiveAlbumResume: (track: Track, position: Double)? {
        guard let albumId = currentAlbumPage?.album.id else { return nil }
        let local = albumLocalPositions[albumId]?.first
        let cloud = albumResumeRecord
        switch (local, cloud) {
        case let (l?, c?):
            return l.atMillis >= c.updatedAtMillis
                ? (l.track, l.positionSeconds)
                : (c.track, c.positionSeconds)
        case let (l?, nil):
            return (l.track, l.positionSeconds)
        case let (nil, c?):
            return (c.track, c.positionSeconds)
        case (nil, nil):
            return nil
        }
    }

    public func openAlbum(_ albumId: String) {
        openedAlbumId = albumId
        albumAscending = true
        albumSelectedSegment = nil
        albumResumeRecord = nil
        albumError = nil
        albumLoading = true
        currentAlbumPage = nil

        Task {
            do {
                let currentClient = client
                async let pageTask = currentClient.album(albumId: albumId, page: 1, ascending: true)
                async let resumeTask: HistoryRecord? = {
                    guard currentClient.accountAvailable else { return nil }
                    let hist = XmlyHistory(client: currentClient)
                    let newest = (try? await hist.newest(limit: 80)) ?? []
                    let cleanId = (try? XmlyIdentifiers.xmlyIdentifier(albumId)) ?? albumId
                    return newest.first { $0.track.albumKey == cleanId }
                }()
                let page = try await pageTask
                let resume = await resumeTask
                guard openedAlbumId == albumId else { return }
                currentAlbumPage = page
                albumResumeRecord = resume
                let total = max(page.total, page.tracks.count)
                if total > 100 {
                    albumSelectedSegment = EpisodeSegment(start: 1, end: min(100, total))
                }
                albumLoading = false
            } catch {
                guard openedAlbumId == albumId else { return }
                albumLoading = false
                albumError = describe(error)
            }
        }
    }

    public func closeAlbum() {
        openedAlbumId = nil
        currentAlbumPage = nil
        albumSelectedSegment = nil
        albumResumeRecord = nil
        albumError = nil
    }

    public func toggleAlbumSortOrder() {
        guard let albumId = currentAlbumPage?.album.id else { return }
        albumAscending.toggle()
        albumSelectedSegment = nil
        albumLoading = true
        Task {
            do {
                let page = try await client.album(albumId: albumId, page: 1, ascending: albumAscending)
                currentAlbumPage = page
                albumLoading = false
            } catch {
                albumLoading = false
                showToast(describe(error))
            }
        }
    }

    /// 切换专辑 100 集分段（若当前尚未加载该区间，自动补拉对应 200 集分页）
    public func selectAlbumSegment(_ segment: EpisodeSegment?) {
        guard let page = currentAlbumPage else { return }
        guard let segment else {
            albumSelectedSegment = nil
            return
        }
        albumSelectedSegment = segment
        // 倒序模式直接展示当前已拉取页或正序分页覆盖
        if !albumAscending { return }
        if page.tracks.count >= segment.end { return }

        albumSegmentBusy = true
        Task {
            do {
                let firstNeededPage = (page.tracks.count / xmlyAlbumPageSize) + 1
                let lastNeededPage = (segment.end + xmlyAlbumPageSize - 1) / xmlyAlbumPageSize
                var merged = page.tracks
                var seen = Set(merged.map(\.id))
                if firstNeededPage <= lastNeededPage {
                    for p in firstNeededPage...lastNeededPage {
                        let fetched = try await client.album(albumId: page.album.id, page: p, ascending: true)
                        for t in fetched.tracks where seen.insert(t.id).inserted {
                            merged.append(t)
                        }
                    }
                }
                merged.sort { ($0.displayOrder ?? Int.max) < ($1.displayOrder ?? Int.max) }
                if currentAlbumPage?.album.id == page.album.id {
                    currentAlbumPage = AlbumPage(
                        album: page.album,
                        tracks: merged,
                        page: page.page,
                        pageSize: page.pageSize,
                        total: max(page.total, merged.count)
                    )
                }
                albumSegmentBusy = false
            } catch {
                albumSegmentBusy = false
                showToast(describe(error))
            }
        }
    }

    // MARK: - 书单（听更新 / 订阅 / 历史 / 收藏）

    public func refreshLibrary() async {
        guard signedIn else {
            updates = []
            subscriptions = []
            historyRecords = []
            favorites = []
            subscribedAlbumIds = []
            favoriteTrackIds = []
            return
        }
        libraryLoading = true
        libraryError = nil
        let exp = XmlyExperience(client: client)
        let hist = XmlyHistory(client: client)

        async let subsResult: Result<SubscriptionPage, Error> = capture { try await exp.subscriptions(page: 1) }
        async let updResult: Result<UpdatePage, Error> = capture { try await exp.updates(before: nil) }
        async let histResult: Result<[HistoryRecord], Error> = capture { try await hist.records() }
        async let favResult: Result<FavoritePage, Error> = capture { try await exp.favorites(page: 1) }

        let (sRes, uRes, hRes, fRes) = await (subsResult, updResult, histResult, favResult)
        var errors: [String] = []

        switch sRes {
        case .success(let page):
            subscriptions = page.items
            subscriptionsHasMore = page.hasMore
            subscriptionsPage = 1
            subscribedAlbumIds = Set(page.items.map(\.album.id))
        case .failure(let err):
            if subscriptions.isEmpty { errors.append("订阅：\(describe(err))") }
        }

        switch uRes {
        case .success(let page):
            updates = page.items
            updatesHasMore = page.hasMore
            updatesNextTimeline = page.nextTimeline
        case .failure(let err):
            if updates.isEmpty { errors.append("更新：\(describe(err))") }
        }

        switch hRes {
        case .success(let list):
            historyRecords = list
        case .failure(let err):
            if historyRecords.isEmpty { errors.append("历史：\(describe(err))") }
        }

        switch fRes {
        case .success(let page):
            favorites = page.items
            favoritesHasMore = page.hasMore
            favoritesPage = 1
            favoriteTrackIds = Set(page.items.map(\.id))
        case .failure(let err):
            if favorites.isEmpty { errors.append("收藏：\(describe(err))") }
        }

        libraryLoading = false
        if !errors.isEmpty {
            libraryError = errors.joined(separator: "；")
        }
    }

    public func loadMoreSubscriptions() async {
        guard signedIn, subscriptionsHasMore else { return }
        do {
            let next = try await XmlyExperience(client: client).subscriptions(page: subscriptionsPage + 1)
            subscriptionsPage += 1
            let existing = Set(subscriptions.map(\.id))
            let added = next.items.filter { !existing.contains($0.id) }
            subscriptions.append(contentsOf: added)
            subscribedAlbumIds.formUnion(added.map(\.album.id))
            subscriptionsHasMore = next.hasMore
        } catch {
            showToast(describe(error))
        }
    }

    public func loadMoreUpdates() async {
        guard signedIn, updatesHasMore, let cursor = updatesNextTimeline else { return }
        do {
            let next = try await XmlyExperience(client: client).updates(before: cursor)
            let existing = Set(updates.map(\.id))
            updates.append(contentsOf: next.items.filter { !existing.contains($0.id) })
            updatesHasMore = next.hasMore
            updatesNextTimeline = next.nextTimeline
        } catch {
            showToast(describe(error))
        }
    }

    public func loadMoreFavorites() async {
        guard signedIn, favoritesHasMore else { return }
        do {
            let next = try await XmlyExperience(client: client).favorites(page: favoritesPage + 1)
            favoritesPage += 1
            let existing = Set(favorites.map(\.id))
            let added = next.items.filter { !existing.contains($0.id) }
            favorites.append(contentsOf: added)
            favoriteTrackIds.formUnion(added.map(\.id))
            favoritesHasMore = next.hasMore
        } catch {
            showToast(describe(error))
        }
    }

    public func toggleSubscribe(album: Album) {
        guard signedIn else {
            showLoginSheet = true
            return
        }
        let target = !subscribedAlbumIds.contains(album.id)
        Task {
            do {
                try await XmlyExperience(client: client).setSubscribed(albumId: album.id, subscribed: target)
                if target {
                    subscribedAlbumIds.insert(album.id)
                    showToast("已订阅《\(album.title)》")
                } else {
                    subscribedAlbumIds.remove(album.id)
                    subscriptions.removeAll { $0.album.id == album.id }
                    showToast("已取消订阅")
                }
            } catch {
                showToast(describe(error))
            }
        }
    }

    public func toggleFavorite(track: Track) {
        guard signedIn else {
            showLoginSheet = true
            return
        }
        let target = !favoriteTrackIds.contains(track.id)
        Task {
            do {
                try await XmlyExperience(client: client).setFavorite(track: track, favorite: target)
                if target {
                    favoriteTrackIds.insert(track.id)
                    if !favorites.contains(where: { $0.id == track.id }) {
                        favorites.insert(track, at: 0)
                    }
                    showToast("已收藏声音")
                } else {
                    favoriteTrackIds.remove(track.id)
                    favorites.removeAll { $0.id == track.id }
                    showToast("已取消收藏")
                }
            } catch {
                showToast(describe(error))
            }
        }
    }

    public func deleteHistoryRecord(_ record: HistoryRecord) {
        guard signedIn else { return }
        Task {
            do {
                try await XmlyHistory(client: client).delete(record: record)
                historyRecords.removeAll { $0.id == record.id }
                showToast("已删除该条收听历史")
            } catch {
                showToast(describe(error))
            }
        }
    }

    // MARK: - 播放与队列控制

    /// 播放当前专辑内选中的声音，并将当前分段（或全页）设为播放队列
    public func playFromCurrentAlbum(track: Track, resumeSeconds: Double = 0) {
        let list = displayedAlbumTracks.isEmpty ? (currentAlbumPage?.tracks ?? [track]) : displayedAlbumTracks
        let idx = list.firstIndex(where: { $0.id == track.id }) ?? 0
        playQueue(list, index: idx, resumeSeconds: resumeSeconds, fullSource: currentAlbumPage?.tracks ?? list, segment: albumSelectedSegment)
    }

    /// 从搜索、历史或听更新播放单集时，自动定位所属专辑分页作为队列，支持连续下一集
    public func playTrackInAlbumContext(_ track: Track, resumeSeconds: Double = 0) {
        guard !track.albumKey.isEmpty else {
            playQueue([track], index: 0, resumeSeconds: resumeSeconds)
            return
        }
        // 先立刻播放目标集减少等待感，再静默补全所属专辑邻近队列
        playQueue([track], index: 0, resumeSeconds: resumeSeconds)
        let reqAtLaunch = playRequestId
        Task {
            let hint = track.displayOrder ?? XmlyIdentifiers.episodeHint(from: track.title)
            if let page = try? await client.albumPageWith(albumId: track.albumKey, trackId: track.id, hintOrdinal: hint),
               reqAtLaunch == playRequestId,
               let idx = page.tracks.firstIndex(where: { $0.id == track.id }) {
                queueAll = page.tracks
                queue = page.tracks
                queueIndex = idx
                queueSegment = nil
            }
        }
    }

    public func playQueue(
        _ newQueue: [Track],
        index: Int,
        resumeSeconds: Double = 0,
        fullSource: [Track]? = nil,
        segment: EpisodeSegment? = nil
    ) {
        guard newQueue.indices.contains(index) else { return }
        let target = newQueue[index]

        if currentTrack != nil && currentTrack?.id != target.id {
            flushProgressAndBilling()
        }

        queueAll = fullSource ?? newQueue
        queue = newQueue
        queueIndex = index
        queueSegment = segment
        currentTrack = target
        isResolving = true
        activeSmartTrim = nil
        smartTrimTask?.cancel()
        unbilledRewardSeconds = 0

        playRequestId += 1
        let requestToken = playRequestId

        updateAmbientColor(for: target.coverUrl)

        Task {
            do {
                let resolved = try await client.resolve(number: target.number, quality: preferences.quality)
                guard requestToken == playRequestId else { return }

                let playedTrack = mergeTrackMetadata(resolved: resolved.track, fallback: target)
                let durationSec = playedTrack.duration > 0 ? playedTrack.duration : target.duration
                let startAt: Double
                if resumeSeconds > 0 {
                    startAt = min(resumeSeconds, max(0, durationSec - 2))
                } else {
                    startAt = computeManualIntroSeek(duration: durationSec)
                }

                currentTrack = playedTrack
                playingQuality = resolved.actualQuality
                sessionStartedAtMillis = Int64(Date().timeIntervalSince1970 * 1000)
                sessionRequiresReward = resolved.requiresReward
                unbilledRewardSeconds = 0
                lastTickAt = Date()
                secondsSinceProgressSync = 0
                isResolving = false
                recoverTrackId = nil
                recoverAttempts = 0

                engine.start(
                    urlString: resolved.url,
                    mediaId: playedTrack.id,
                    expectedDuration: durationSec,
                    startPosition: startAt,
                    rate: preferences.speed,
                    volume: preferences.volume
                )
                updateNowPlayingInfo()
                syncProgressToStorageAndCloud()

                // 若启用智能跳过头尾且从头播放，后台静默检测首尾静音区间
                if preferences.skipTrimEnabled && preferences.skipTrimMode == .smart,
                   let streamURL = URL(string: resolved.url) {
                    smartTrimTask = Task { [weak self] in
                        let trim = await Task.detached(priority: .utility) {
                            await SmartSilenceAnalyzer.analyze(url: streamURL, duration: durationSec)
                        }.value
                        guard let self, self.playRequestId == requestToken, let trim else { return }
                        self.activeSmartTrim = trim
                        if resumeSeconds <= 0 && trim.introEndSeconds > 0.6 && self.clock.currentTime < trim.introEndSeconds {
                            self.engine.seek(to: trim.introEndSeconds)
                        }
                    }
                }
            } catch {
                guard requestToken == playRequestId else { return }
                isResolving = false
                isPlaying = false
                showToast(describe(error))
            }
        }
    }

    public func togglePlayPause() {
        if currentTrack == nil {
            if !queue.isEmpty {
                playQueue(queue, index: 0)
            } else if let resume = historyRecords.first {
                playTrackInAlbumContext(resume.track, resumeSeconds: resume.positionSeconds)
            }
            return
        }
        if isPlaying {
            engine.pause()
            flushProgressAndBilling()
        } else {
            lastTickAt = Date()
            engine.play()
        }
        updateNowPlayingInfo()
    }

    public func playNext() {
        guard !queue.isEmpty else { return }
        let nextIdx = queueIndex + 1
        guard queue.indices.contains(nextIdx) else {
            showToast("已是当前队列最后一集")
            return
        }
        playQueue(queue, index: nextIdx, fullSource: queueAll, segment: queueSegment)
    }

    public func playPrevious() {
        guard !queue.isEmpty else { return }
        let prevIdx = queueIndex - 1
        guard queue.indices.contains(prevIdx) else {
            engine.seek(to: 0)
            return
        }
        playQueue(queue, index: prevIdx, fullSource: queueAll, segment: queueSegment)
    }

    public func seek(to seconds: Double) {
        engine.seek(to: seconds)
        updateNowPlayingInfo()
    }

    public func skip(by seconds: Double) {
        engine.skip(by: seconds)
        updateNowPlayingInfo()
    }

    /// 队列按 100 集区间筛选
    public var queueSegments: [EpisodeSegment] {
        let maxOrder = queueAll.compactMap(\.displayOrder).max() ?? queueAll.count
        guard maxOrder > 100 else { return [] }
        return EpisodeSegment.makeSegments(total: maxOrder, chunkSize: 100)
    }

    public func setQueueSegment(_ segment: EpisodeSegment?) {
        let base = queueAll.isEmpty ? queue : queueAll
        guard !base.isEmpty else { return }
        guard let segment else {
            queueSegment = nil
            queue = base
            queueIndex = base.firstIndex(where: { $0.id == currentTrack?.id }) ?? 0
            return
        }
        let filtered = base.enumerated().compactMap { idx, track -> Track? in
            let ord = track.displayOrder ?? (idx + 1)
            return (segment.start...segment.end).contains(ord) ? track : nil
        }
        guard !filtered.isEmpty else { return }
        queueSegment = segment
        queue = filtered
        queueIndex = filtered.firstIndex(where: { $0.id == currentTrack?.id }) ?? 0
    }

    public func setSpeed(_ newSpeed: Double) {
        preferences.speed = AppPreferences.normalizeSpeed(newSpeed)
        updateNowPlayingInfo()
    }

    public func setQuality(_ newQuality: String) {
        preferences.quality = newQuality
        // 如果正在播放，无缝在当前位置按新音质重新解析
        if let track = currentTrack, isPlaying {
            let pos = clock.currentTime
            playQueue(queue.isEmpty ? [track] : queue, index: queueIndex, resumeSeconds: pos, fullSource: queueAll, segment: queueSegment)
        }
    }

    public func setSleepTimer(_ option: SleepTimerOption) {
        sleepTimerOption = option
        switch option {
        case .off, .endOfTrack:
            sleepDeadline = nil
            sleepRemainingSeconds = 0
        case .minutes(let mins):
            let deadline = Date().addingTimeInterval(Double(mins * 60))
            sleepDeadline = deadline
            sleepRemainingSeconds = mins * 60
        }
    }

    // MARK: - 账号管理与听时福利

    public func importCookie(_ rawText: String) async throws {
        accountBusy = true
        defer { accountBusy = false }
        let parsed = try Credentials.parse(rawText)
        let candidateClient = XmlyClient(http: http, credentials: parsed)
        let fetchedProfile = try? await XmlyExperience(client: candidateClient).profile()
        let fetchedQuota = try? await candidateClient.quota()
        try applySignedInAccount(parsed, profile: fetchedProfile, quota: fetchedQuota)
        showToast("已导入并登录账号")
    }

    public func completeSmsLogin(_ result: LoginResult) async throws {
        accountBusy = true
        defer { accountBusy = false }
        let candidateClient = XmlyClient(http: http, credentials: result.credentials)
        let remoteProfile = try? await XmlyExperience(client: candidateClient).profile()
        let mergedProfile = remoteProfile ?? UserProfile(
            uid: result.credentials.uid,
            nickname: result.nickname,
            avatarUrl: result.avatarUrl
        )
        let fetchedQuota = try? await candidateClient.quota()
        try applySignedInAccount(result.credentials, profile: mergedProfile, quota: fetchedQuota)
        showToast("手机号登录成功")
    }

    public func signOut() {
        flushProgressAndBilling()
        try? storage.saveCredentials(nil)
        storage.saveProfile(nil)
        credentials = nil
        profile = nil
        quota = nil
        rewardTiers = []
        rewardStatusNote = ""
        client = XmlyClient(http: http, credentials: nil)
        homeCache.removeAll()
        updates = []
        subscriptions = []
        historyRecords = []
        favorites = []
        subscribedAlbumIds = []
        favoriteTrackIds = []
        showToast("已退出登录")
    }

    public func refreshAccountSummary() async {
        guard signedIn else { return }
        accountBusy = true
        defer { accountBusy = false }
        let currentClient = client
        async let profileTask: UserProfile? = try? await XmlyExperience(client: currentClient).profile()
        async let quotaTask: Quota? = try? await currentClient.quota()
        async let tiersTask: [RewardTier] = (try? await XmlyRewards(client: currentClient).tiers()) ?? []

        if let p = await profileTask {
            profile = p
            storage.saveProfile(p)
        }
        if let q = await quotaTask {
            quota = q
        }
        rewardTiers = await tiersTask
    }

    public func claimRewardsNow() async {
        guard signedIn else {
            showLoginSheet = true
            return
        }
        rewardsBusy = true
        defer { rewardsBusy = false }
        do {
            let rewards = XmlyRewards(client: client)
            let outcome = try await rewards.refresh(enabled: true)
            quota = outcome.quota
            rewardStatusNote = outcome.note
            rewardTiers = (try? await rewards.tiers()) ?? rewardTiers
            showToast(outcome.note.isEmpty ? "听时已刷新" : outcome.note)
        } catch {
            rewardStatusNote = describe(error)
            showToast(describe(error))
        }
    }

    public func copyExportableCookie() {
        guard let creds = credentials else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(creds.cookie, forType: .string)
        showToast("已复制登录 Cookie 到剪贴板")
    }

    /// 应用退出或休眠前强制落盘进度并上报未结算听时
    public func handleApplicationWillTerminate() {
        flushProgressAndBilling()
    }

    // MARK: - 内部生命周期与后台轮询

    private func applySignedInAccount(_ creds: Credentials, profile: UserProfile?, quota: Quota?) throws {
        try storage.saveCredentials(creds)
        credentials = creds
        client = XmlyClient(http: http, credentials: creds)
        if let profile {
            self.profile = profile
            storage.saveProfile(profile)
        }
        if let quota {
            self.quota = quota
        }
        homeCache.removeAll()
        Task {
            await refreshAccountSummary()
            await refreshLibrary()
            await loadHome(force: true)
            if preferences.autoClaimRewards {
                await runSilentAutoClaim()
            }
        }
    }

    private func wirePlayerCallbacks() {
        engine.onStateChanged = { [weak self] playing, buffering in
            guard let self else { return }
            self.isPlaying = playing
            self.isBuffering = buffering
            if playing {
                self.lastTickAt = Date()
            }
            self.updateNowPlayingInfo()
        }

        engine.onTrackEnded = { [weak self] mediaId in
            guard let self, self.currentTrack?.id == mediaId else { return }
            self.flushProgressAndBilling()
            if self.sleepTimerOption == .endOfTrack {
                self.sleepTimerOption = .off
                self.showToast("已播完本集并自动暂停")
                return
            }
            let nextIdx = self.queueIndex + 1
            if self.queue.indices.contains(nextIdx) {
                self.playQueue(self.queue, index: nextIdx, fullSource: self.queueAll, segment: self.queueSegment)
            }
        }

        engine.onFailure = { [weak self] mediaId, message, position in
            guard let self, let track = self.currentTrack, track.id == mediaId else { return }
            if self.recoverTrackId != mediaId {
                self.recoverTrackId = mediaId
                self.recoverAttempts = 0
            }
            if self.recoverAttempts < 3 {
                self.recoverAttempts += 1
                self.showToast("连接中断，正在第 \(self.recoverAttempts) 次自动续播…")
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard let self, self.currentTrack?.id == mediaId else { return }
                    self.playQueue(self.queue.isEmpty ? [track] : self.queue, index: self.queueIndex, resumeSeconds: position, fullSource: self.queueAll, segment: self.queueSegment)
                }
            } else {
                self.showToast(message)
            }
        }
    }

    private func wireRemoteCommands() {
        nowPlaying.installCommands()
        nowPlaying.onPlay = { [weak self] in self?.engine.play() }
        nowPlaying.onPause = { [weak self] in
            self?.engine.pause()
            self?.flushProgressAndBilling()
        }
        nowPlaying.onTogglePlayPause = { [weak self] in self?.togglePlayPause() }
        nowPlaying.onNext = { [weak self] in self?.playNext() }
        nowPlaying.onPrevious = { [weak self] in self?.playPrevious() }
        nowPlaying.onSeek = { [weak self] pos in self?.seek(to: pos) }
        nowPlaying.onSkipForward = { [weak self] sec in self?.skip(by: sec) }
        nowPlaying.onSkipBackward = { [weak self] sec in self?.skip(by: -sec) }
    }

    private func startBackgroundLoops() {
        tickerTask?.cancel()
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { break }
                self.handleHalfSecondTick()
            }
        }

        autoClaimTask?.cancel()
        autoClaimTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                guard let self else { break }
                if self.signedIn && self.preferences.autoClaimRewards {
                    await self.runSilentAutoClaim()
                }
            }
        }
    }

    private func handleHalfSecondTick() {
        // 1. 睡眠倒计时检查
        if let deadline = sleepDeadline {
            let rem = Int(ceil(deadline.timeIntervalSinceNow))
            if rem <= 0 {
                sleepDeadline = nil
                sleepRemainingSeconds = 0
                sleepTimerOption = .off
                if isPlaying {
                    engine.pause()
                    flushProgressAndBilling()
                    showToast("定时关闭已到点暂停")
                }
            } else {
                sleepRemainingSeconds = rem
            }
        }

        guard isPlaying, currentTrack != nil else { return }
        let now = Date()
        let delta = min(max(now.timeIntervalSince(lastTickAt), 0), 2.0)
        lastTickAt = now

        // 2. 跳过片尾判定（手动比例模式或智能静音尾段）
        let dur = clock.duration
        let pos = clock.currentTime
        if preferences.skipTrimEnabled && dur > 10 {
            if preferences.skipTrimMode == .manual && preferences.outroSkipPermille > 0 {
                let outro = dur * Double(preferences.outroSkipPermille) / 1000.0
                if dur > outro + 2.5 && pos >= dur - outro {
                    advanceAfterOutroSkip()
                    return
                }
            } else if preferences.skipTrimMode == .smart, let outroStart = activeSmartTrim?.outroStartSeconds {
                if pos >= outroStart {
                    advanceAfterOutroSkip()
                    return
                }
            }
        }

        // 3. 累计同步进度与付费听时扣减
        secondsSinceProgressSync += delta
        if sessionRequiresReward {
            unbilledRewardSeconds += delta
            if unbilledRewardSeconds >= 60 {
                let toDebit = Int(unbilledRewardSeconds)
                unbilledRewardSeconds -= Double(toDebit)
                reportRewardUsage(seconds: toDebit)
            }
        }

        if secondsSinceProgressSync >= 60 {
            secondsSinceProgressSync = 0
            syncProgressToStorageAndCloud()
        }
    }

    private func advanceAfterOutroSkip() {
        flushProgressAndBilling()
        let nextIdx = queueIndex + 1
        if queue.indices.contains(nextIdx) {
            playQueue(queue, index: nextIdx, fullSource: queueAll, segment: queueSegment)
        } else {
            engine.pause()
        }
    }

    private func computeManualIntroSeek(duration: Double) -> Double {
        guard preferences.skipTrimEnabled,
              preferences.skipTrimMode == .manual,
              preferences.introSkipPermille > 0,
              duration > 5 else {
            return 0
        }
        return duration * Double(preferences.introSkipPermille) / 1000.0
    }

    private func flushProgressAndBilling() {
        syncProgressToStorageAndCloud()
        if sessionRequiresReward && unbilledRewardSeconds >= 5 {
            let secs = Int(unbilledRewardSeconds.rounded())
            unbilledRewardSeconds = 0
            reportRewardUsage(seconds: secs)
        }
    }

    private func syncProgressToStorageAndCloud() {
        guard let track = currentTrack else { return }
        let pos = clock.currentTime
        albumLocalPositions = storage.rememberPosition(track: track, positionSeconds: pos)

        guard signedIn, sessionStartedAtMillis > 0, !track.albumKey.isEmpty else { return }
        let started = sessionStartedAtMillis
        let ended = max(Int64(Date().timeIntervalSince1970 * 1000), started)
        let activeClient = client
        Task.detached(priority: .utility) {
            let hist = XmlyHistory(client: activeClient)
            try? await hist.sync(track: track, positionSeconds: pos, startedAtMillis: started, endedAtMillis: ended)
        }
    }

    private func reportRewardUsage(seconds: Int) {
        guard signedIn, seconds >= 1 else { return }
        let activeClient = client
        Task { [weak self] in
            if let updated = try? await activeClient.debit(seconds: seconds) {
                self?.quota = updated
            }
        }
    }

    private func runSilentAutoClaim() async {
        guard signedIn else { return }
        let rewards = XmlyRewards(client: client)
        if let outcome = try? await rewards.refresh(enabled: true) {
            quota = outcome.quota
            rewardStatusNote = outcome.note
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            nowPlaying.clear()
            return
        }
        nowPlaying.update(
            title: track.title,
            artist: track.artist.isEmpty ? track.album : track.artist,
            album: track.album,
            duration: clock.duration > 0 ? clock.duration : track.duration,
            elapsed: clock.currentTime,
            rate: preferences.speed,
            isPlaying: isPlaying,
            artworkUrl: track.coverUrl
        )
    }

    private func updateAmbientColor(for coverUrl: String?) {
        Task { [weak self] in
            let color = await ArtworkManager.shared.accentColor(for: coverUrl)
            withAnimation(.easeInOut(duration: 0.6)) {
                self?.ambientColor = color
            }
        }
    }

    private func mergeTrackMetadata(resolved: Track, fallback: Track) -> Track {
        (try? Track(
            rawId: resolved.number,
            title: resolved.title.isEmpty ? fallback.title : resolved.title,
            artist: resolved.artist.isEmpty ? fallback.artist : resolved.artist,
            album: resolved.album.isEmpty ? fallback.album : resolved.album,
            albumId: resolved.albumKey.isEmpty ? fallback.albumKey : resolved.albumKey,
            duration: resolved.duration > 0 ? resolved.duration : fallback.duration,
            orderNo: resolved.orderNo ?? fallback.orderNo,
            episode: resolved.episode ?? fallback.episode,
            officialPosition: resolved.officialPosition ?? fallback.officialPosition,
            isPaid: resolved.isPaid ?? fallback.isPaid,
            isAuthorized: resolved.isAuthorized ?? fallback.isAuthorized,
            coverUrl: resolved.coverUrl ?? fallback.coverUrl,
            intro: resolved.intro.isEmpty ? fallback.intro : resolved.intro,
            direction: resolved.direction
        )) ?? resolved
    }

    private func capture<T>(_ block: () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await block())
        } catch {
            return .failure(error)
        }
    }

    private func describe(_ error: Error) -> String {
        if let xmly = error as? XmlyException {
            return xmly.message
        }
        return error.localizedDescription
    }
}
