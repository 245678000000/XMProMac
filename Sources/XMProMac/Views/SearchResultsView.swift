import SwiftUI
import XMProCore

/// 搜索结果视图：支持专辑网格与声音列表切换及分页加载
struct SearchResultsView: View {
    @Bindable var store: AppStore

    private let albumCols = [
        GridItem(.adaptive(minimum: 152, maximum: 196), spacing: 18),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    store.clearSearch()
                } label: {
                    Label("返回", systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Text("搜索“\(store.searchQuery)”")
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(1)

                if store.searchTotal > 0 {
                    Text("\(store.searchTotal) 条结果")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("", selection: $store.searchKind) {
                    Text("专辑").tag("album")
                    Text("声音").tag("track")
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .onChange(of: store.searchKind) { _, _ in
                    Task { await store.performSearch(reset: true) }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Divider().opacity(0.5)

            if store.searchLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在搜索…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = store.searchError {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "搜索出错",
                    subtitle: err,
                    buttonTitle: "重试"
                ) {
                    Task { await store.performSearch(reset: true) }
                }
            } else if store.searchKind == "album" {
                if store.searchAlbums.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "没有找到相关专辑", subtitle: "试试更换关键词或切换到“声音”标签")
                } else {
                    ScrollView {
                        LazyVGrid(columns: albumCols, spacing: 22) {
                            ForEach(store.searchAlbums) { album in
                                AlbumCardView(album: album) {
                                    store.openAlbum(album.id)
                                }
                            }
                        }
                        .padding(.horizontal, 26)
                        .padding(.top, 20)

                        loadMoreFooter
                            .padding(.bottom, 118)
                    }
                }
            } else {
                if store.searchTracks.isEmpty {
                    EmptyStateView(icon: "waveform", title: "没有找到相关声音", subtitle: "试试更换关键词或切换到“专辑”标签")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(store.searchTracks) { track in
                                searchTrackRow(track)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

                        loadMoreFooter
                            .padding(.bottom, 118)
                    }
                }
            }
        }
    }

    private func searchTrackRow(_ track: Track) -> some View {
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
                HStack(spacing: 8) {
                    if !track.album.isEmpty {
                        Text(track.album).lineLimit(1)
                    }
                    if !track.artist.isEmpty {
                        Text("· \(track.artist)").lineLimit(1)
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

    @ViewBuilder
    private var loadMoreFooter: some View {
        if store.canLoadMoreSearch {
            HStack {
                Spacer()
                if store.searchLoadingMore {
                    ProgressView().controlSize(.small)
                } else {
                    Button("加载更多") {
                        Task { await store.performSearch(reset: false) }
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
            .padding(.top, 18)
        }
    }
}
