import SwiftUI
import XMProCore

/// 探索发现主页：频道胶囊条、二级分类、排行榜与推荐流网格
struct DiscoverView: View {
    @Bindable var store: AppStore

    private let gridColumns = [
        GridItem(.adaptive(minimum: 152, maximum: 196), spacing: 18),
    ]

    var body: some View {
        VStack(spacing: 0) {
            channelHeaderBar

            Divider().opacity(0.5)

            if store.homeLoading && store.homeSections.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在为你发现精彩声音…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.homeError, store.homeSections.isEmpty {
                EmptyStateView(
                    icon: "wifi.exclamationmark",
                    title: "加载首页失败",
                    subtitle: error,
                    buttonTitle: "重新加载"
                ) {
                    Task { await store.loadHome(force: true) }
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        if !store.homeTabs.isEmpty {
                            subTabStrip
                        }

                        ForEach(store.homeSections) { section in
                            sectionView(section)
                        }
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 20)
                    .padding(.bottom, 118)
                }
            }
        }
    }

    private var channelHeaderBar: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.channels) { channel in
                        PillChip(
                            title: channel.title,
                            selected: store.selectedChannelId == channel.pageId
                        ) {
                            Task { await store.selectChannel(channel.pageId, tabId: nil) }
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Button {
                Task {
                    if let id = store.selectedChannelId {
                        await store.selectChannel(id, tabId: store.selectedTabId, force: true)
                    } else {
                        await store.loadHome(force: true)
                    }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)
            .help("刷新当前频道")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var subTabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PillChip(title: "全部", selected: store.selectedTabId == nil) {
                    if let id = store.selectedChannelId {
                        Task { await store.selectChannel(id, tabId: nil) }
                    }
                }
                ForEach(store.homeTabs) { tab in
                    PillChip(title: tab.title, selected: store.selectedTabId == tab.tabId) {
                        if let id = store.selectedChannelId {
                            Task { await store.selectChannel(id, tabId: tab.tabId) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title)
                    .font(.system(size: 19, weight: .bold))
                if section.isRanking {
                    Text("热门榜")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.14), in: Capsule())
                }
                Spacer()
            }

            if section.isRanking {
                rankingGrid(section)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 22) {
                    ForEach(section.albums) { album in
                        let stat = section.stats[album.id]
                        AlbumCardView(
                            album: album,
                            stats: stat,
                            badgeText: stat?.finished == true ? "完结" : nil
                        ) {
                            store.openAlbum(album.id)
                        }
                    }
                }
            }
        }
    }

    private func rankingGrid(_ section: HomeSection) -> some View {
        let cols = [
            GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 14),
        ]
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(Array(section.albums.enumerated()), id: \.element.id) { index, album in
                Button {
                    store.openAlbum(album.id)
                } label: {
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(index < 3 ? Color.orange : Color.secondary)
                            .frame(width: 24)

                        ArtworkImageView(urlString: album.coverUrl, cornerRadius: 8, shadowRadius: 2)
                            .frame(width: 52, height: 52)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(album.title)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(album.artist.isEmpty ? "共 \(album.total) 集" : album.artist)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.038), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
