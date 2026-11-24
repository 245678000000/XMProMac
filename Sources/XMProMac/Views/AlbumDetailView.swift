import SwiftUI
import XMProCore

/// 专辑详情页：苹果播客式头图、智能续播按钮、100 集分段选集网格与剧集清单
struct AlbumDetailView: View {
    @Bindable var store: AppStore

    @State private var introExpanded = false
    @State private var hoveredTrackId: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // 顶部极简导航栏
            HStack(spacing: 10) {
                Button {
                    store.closeAlbum()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("返回")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.055), in: Capsule())
                }
                .buttonStyle(.plain)

                if let album = store.currentAlbumPage?.album {
                    Text(album.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if store.currentAlbumPage != nil {
                    Button {
                        store.toggleAlbumSortOrder()
                    } label: {
                        Label(store.albumAscending ? "正序" : "倒序", systemImage: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 11)

            Divider().opacity(0.5)

            if store.albumLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在加载专辑目录…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = store.albumError {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "无法加载专辑",
                    subtitle: err,
                    buttonTitle: "重试"
                ) {
                    if let id = store.openedAlbumId {
                        store.openAlbum(id)
                    }
                }
            } else if let page = store.currentAlbumPage {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        albumHeroHeader(page)

                        if store.albumSegments.count > 1 && store.albumAscending {
                            segmentPickerBar
                        }

                        trackListSection
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 22)
                    .padding(.bottom, 120)
                }
            }
        }
    }

    private func albumHeroHeader(_ page: AlbumPage) -> some View {
        let album = page.album
        let subscribed = store.subscribedAlbumIds.contains(album.id)
        let resume = store.effectiveAlbumResume

        return HStack(alignment: .top, spacing: 22) {
            ArtworkImageView(urlString: album.coverUrl, cornerRadius: 16, shadowRadius: 14)
                .frame(width: 164, height: 164)

            VStack(alignment: .leading, spacing: 10) {
                Text(album.title.isEmpty ? "未命名专辑" : album.title)
                    .font(.system(size: 24, weight: .bold))
                    .lineLimit(2)

                HStack(spacing: 12) {
                    if !album.artist.isEmpty {
                        Label(album.artist, systemImage: "mic.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Label("共 \(max(page.total, page.tracks.count)) 集", systemImage: "list.number")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                if !album.intro.isEmpty {
                    Text(album.intro)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(introExpanded ? nil : 2)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                introExpanded.toggle()
                            }
                        }
                        .help("点击展开或收起简介")
                }

                Spacer(minLength: 4)

                HStack(spacing: 10) {
                    if let resume {
                        Button {
                            store.playTrackInAlbumContext(resume.track, resumeSeconds: resume.position)
                        } label: {
                            Label(
                                "续播 · \(resume.track.title.prefix(16))",
                                systemImage: "play.fill"
                            )
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else if let first = store.displayedAlbumTracks.first ?? page.tracks.first {
                        Button {
                            store.playFromCurrentAlbum(track: first)
                        } label: {
                            Label("开始收听", systemImage: "play.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    Button {
                        store.toggleSubscribe(album: album)
                    } label: {
                        Label(
                            subscribed ? "已订阅" : "订阅专辑",
                            systemImage: subscribed ? "checkmark.circle.fill" : "plus.circle"
                        )
                        .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.032))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        }
    }

    private var segmentPickerBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("选集区间")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                if store.albumSegmentBusy {
                    ProgressView().controlSize(.mini)
                    Text("正在拉取该分段剧集…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.albumSegments) { seg in
                        PillChip(
                            title: seg.label,
                            selected: store.albumSelectedSegment == seg
                        ) {
                            store.selectAlbumSegment(seg)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var trackListSection: some View {
        let tracks = store.displayedAlbumTracks
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(store.albumSelectedSegment.map { "第 \($0.label) 集" } ?? "全部声音")
                    .font(.system(size: 15, weight: .bold))
                Text("(\(tracks.count))")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.bottom, 6)

            if tracks.isEmpty && !store.albumSegmentBusy {
                Text("当前区间暂无声音")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, track in
                        trackRow(track: track, fallbackIndex: idx + 1)
                    }
                }
            }
        }
    }

    private func trackRow(track: Track, fallbackIndex: Int) -> some View {
        let isCurrent = store.currentTrack?.id == track.id
        let isHovered = hoveredTrackId == track.id
        let isFav = store.favoriteTrackIds.contains(track.id)

        return HStack(spacing: 12) {
            ZStack {
                if isCurrent {
                    PlayingBarsIndicator(isPlaying: store.isPlaying, color: store.ambientColor)
                } else if isHovered {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text("\(track.displayOrder ?? fallbackIndex)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 34, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(track.title)
                        .font(.system(size: 13.5, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? store.ambientColor : .primary)
                        .lineLimit(1)

                    if track.isPaid == true {
                        Text(track.isAuthorized == true ? "已购" : "VIP")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(track.isAuthorized == true ? .green : .orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                (track.isAuthorized == true ? Color.green : Color.orange).opacity(0.14),
                                in: Capsule()
                            )
                    }
                }
            }

            Spacer(minLength: 10)

            if isHovered || isFav {
                Button {
                    store.toggleFavorite(track: track)
                } label: {
                    Image(systemName: isFav ? "heart.fill" : "heart")
                        .font(.system(size: 12.5))
                        .foregroundStyle(isFav ? .pink : .secondary)
                }
                .buttonStyle(.plain)
                .help(isFav ? "取消收藏" : "收藏声音")
            }

            if track.duration > 0 {
                Text(TimeFormatter.mmss(track.duration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isCurrent
                        ? store.ambientColor.opacity(0.11)
                        : (isHovered ? Color.primary.opacity(0.05) : Color.clear)
                )
        }
        .contentShape(Rectangle())
        .onHover { hoveredTrackId = $0 ? track.id : nil }
        .onTapGesture {
            store.playFromCurrentAlbum(track: track)
        }
    }
}
