import SwiftUI
import XMProCore

/// 书单四栏视图集合：听更新 / 订阅 / 历史 / 收藏
struct LibrarySectionView: View {
    @Bindable var store: AppStore
    let section: SidebarSection

    private let gridCols = [
        GridItem(.adaptive(minimum: 152, maximum: 196), spacing: 18),
    ]

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.5)

            if !store.signedIn {
                EmptyStateView(
                    icon: "person.crop.circle.badge.plus",
                    title: "登录后查看你的\(section.rawValue)",
                    subtitle: "支持一键导入 XMPro Cookie 或使用手机号短信验证码登录，自动同步你的书单与听书进度。",
                    buttonTitle: "登录喜马拉雅账号"
                ) {
                    store.showLoginSheet = true
                }
            } else if store.libraryLoading && isCurrentSectionEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在同步云端\(section.rawValue)…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                contentBody
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Text(section.rawValue)
                .font(.system(size: 20, weight: .bold))
            Spacer()
            if store.signedIn {
                Button {
                    Task { await store.refreshLibrary() }
                } label: {
                    if store.libraryLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("刷新", systemImage: "arrow.clockwise")
                            .font(.system(size: 12.5, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var isCurrentSectionEmpty: Bool {
        switch section {
        case .updates: return store.updates.isEmpty
        case .subscriptions: return store.subscriptions.isEmpty
        case .history: return store.historyRecords.isEmpty
        case .favorites: return store.favorites.isEmpty
        default: return true
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        switch section {
        case .updates:
            updatesBody
        case .subscriptions:
            subscriptionsBody
        case .history:
            historyBody
        case .favorites:
            favoritesBody
        default:
            EmptyView()
        }
    }

    // MARK: - 听更新
    @ViewBuilder
    private var updatesBody: some View {
        if store.updates.isEmpty {
            EmptyStateView(icon: "dot.radiowaves.left.and.right", title: "暂无订阅更新", subtitle: "你订阅的专辑发布新声音后会第一时间出现在这里")
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.updates) { item in
                        updateRow(item)
                    }
                    if store.updatesHasMore {
                        Button("加载更早更新") {
                            Task { await store.loadMoreUpdates() }
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 14)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 120)
            }
        }
    }

    private func updateRow(_ item: UpdateItem) -> some View {
        let track = item.track
        let isCurrent = store.currentTrack?.id == track.id
        return HStack(spacing: 12) {
            ArtworkImageView(urlString: track.coverUrl, cornerRadius: 8, shadowRadius: 2)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if isCurrent {
                        PlayingBarsIndicator(isPlaying: store.isPlaying, color: store.ambientColor)
                    }
                    Text(track.title)
                        .font(.system(size: 13.5, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(isCurrent ? store.ambientColor : .primary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text(track.album.isEmpty ? track.artist : track.album)
                        .lineLimit(1)
                    let timeStr = TimeFormatter.relativeDate(millis: item.publishedAtMillis)
                    if !timeStr.isEmpty {
                        Text("· \(timeStr)")
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }

            Spacer()

            if track.duration > 0 {
                Text(TimeFormatter.mmss(track.duration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if !track.albumKey.isEmpty {
                Button {
                    store.openAlbum(track.albumKey)
                } label: {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("打开所属专辑")
            }

            Button {
                store.playTrackInAlbumContext(track)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isCurrent ? store.ambientColor.opacity(0.11) : Color.primary.opacity(0.032))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            store.playTrackInAlbumContext(track)
        }
    }

    // MARK: - 订阅
    @ViewBuilder
    private var subscriptionsBody: some View {
        if store.subscriptions.isEmpty {
            EmptyStateView(icon: "square.stack", title: "还没有订阅专辑", subtitle: "在发现或搜索中打开喜欢的专辑即可一键订阅")
        } else {
            ScrollView {
                LazyVGrid(columns: gridCols, spacing: 22) {
                    ForEach(store.subscriptions) { item in
                        AlbumCardView(
                            album: item.album,
                            badgeText: item.unreadCount > 0 ? "+\(min(item.unreadCount, 99))" : nil,
                            subtitleOverride: item.latestTitle.isEmpty ? item.album.artist : item.latestTitle
                        ) {
                            store.openAlbum(item.album.id)
                        }
                        .contextMenu {
                            Button("打开专辑") { store.openAlbum(item.album.id) }
                            Button("取消订阅", role: .destructive) { store.toggleSubscribe(album: item.album) }
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 20)

                if store.subscriptionsHasMore {
                    Button("加载更多订阅") {
                        Task { await store.loadMoreSubscriptions() }
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 16)
                }
                Spacer().frame(height: 120)
            }
        }
    }

    // MARK: - 历史
    @ViewBuilder
    private var historyBody: some View {
        if store.historyRecords.isEmpty {
            EmptyStateView(icon: "clock.arrow.circlepath", title: "暂无收听历史", subtitle: "播放任意声音后会自动记录并同步到云端历史")
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.historyRecords) { record in
                        historyRow(record)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 120)
            }
        }
    }

    private func historyRow(_ record: HistoryRecord) -> some View {
        let track = record.track
        let isCurrent = store.currentTrack?.id == track.id
        let pct = track.duration > 0 ? min(max(record.positionSeconds / track.duration, 0), 1) : 0

        return HStack(spacing: 12) {
            ArtworkImageView(urlString: track.coverUrl, cornerRadius: 8, shadowRadius: 2)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if isCurrent {
                        PlayingBarsIndicator(isPlaying: store.isPlaying, color: store.ambientColor)
                    }
                    Text(track.album.isEmpty ? track.title : track.album)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(isCurrent ? store.ambientColor : .primary)
                        .lineLimit(1)
                }
                Text(track.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.1))
                            Capsule().fill(Color.accentColor.opacity(0.85))
                                .frame(width: geo.size.width * pct)
                        }
                    }
                    .frame(width: 90, height: 3.5)

                    Text("播至 \(TimeFormatter.mmss(record.positionSeconds))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    let rel = TimeFormatter.relativeDate(millis: record.updatedAtMillis)
                    if !rel.isEmpty {
                        Text("· \(rel)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if !track.albumKey.isEmpty {
                Button {
                    store.openAlbum(track.albumKey)
                } label: {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("查看专辑全部剧集")
            }

            Button {
                store.playTrackInAlbumContext(track, resumeSeconds: record.positionSeconds)
            } label: {
                Label("续播", systemImage: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                store.deleteHistoryRecord(record)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("删除此条云端历史")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isCurrent ? store.ambientColor.opacity(0.1) : Color.primary.opacity(0.032))
        )
    }

    // MARK: - 收藏
    @ViewBuilder
    private var favoritesBody: some View {
        if store.favorites.isEmpty {
            EmptyStateView(icon: "heart", title: "还没有收藏声音", subtitle: "在剧集列表或播放器中点击心形即可收藏单集声音")
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.favorites) { track in
                        favoriteRow(track)
                    }
                    if store.favoritesHasMore {
                        Button("加载更多收藏") {
                            Task { await store.loadMoreFavorites() }
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 14)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 120)
            }
        }
    }

    private func favoriteRow(_ track: Track) -> some View {
        let isCurrent = store.currentTrack?.id == track.id
        return HStack(spacing: 12) {
            ArtworkImageView(urlString: track.coverUrl, cornerRadius: 8, shadowRadius: 2)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if isCurrent {
                        PlayingBarsIndicator(isPlaying: store.isPlaying, color: store.ambientColor)
                    }
                    Text(track.title)
                        .font(.system(size: 13.5, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(isCurrent ? store.ambientColor : .primary)
                        .lineLimit(1)
                }
                Text(track.album.isEmpty ? track.artist : track.album)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if track.duration > 0 {
                Text(TimeFormatter.mmss(track.duration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Button {
                store.toggleFavorite(track: track)
            } label: {
                Image(systemName: "heart.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.pink)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("取消收藏")

            Button {
                store.playTrackInAlbumContext(track)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isCurrent ? store.ambientColor.opacity(0.1) : Color.primary.opacity(0.03))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            store.playTrackInAlbumContext(track)
        }
    }
}
