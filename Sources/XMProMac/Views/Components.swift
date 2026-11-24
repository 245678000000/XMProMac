import AppKit
import SwiftUI
import XMProCore

/// 带内存缓存、精致圆角描边与柔和平滑淡入的专辑封面组件
struct ArtworkImageView: View {
    let urlString: String?
    var cornerRadius: CGFloat = 12
    var shadowRadius: CGFloat = 6

    @State private var image: NSImage? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .transition(.opacity.animation(.easeOut(duration: 0.22)))
                } else {
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.22),
                            Color.secondary.opacity(0.14),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Image(systemName: "waveform")
                            .font(.system(size: max(14, geo.size.width * 0.28), weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.65))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(shadowRadius > 0 ? 0.12 : 0), radius: shadowRadius, y: shadowRadius * 0.45)
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: urlString) {
            if let urlString, !urlString.isEmpty {
                image = await ArtworkManager.shared.loadImage(from: urlString)
            } else {
                image = nil
            }
        }
    }
}

/// 苹果播客风格专辑网格卡片
struct AlbumCardView: View {
    let album: Album
    var stats: HomeAlbumStats? = nil
    var badgeText: String? = nil
    var subtitleOverride: String? = nil
    let onTap: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    ArtworkImageView(
                        urlString: album.coverUrl,
                        cornerRadius: 12,
                        shadowRadius: hovered ? 12 : 5
                    )
                    .scaleEffect(hovered ? 1.02 : 1.0)

                    if let badgeText, !badgeText.isEmpty {
                        Text(badgeText)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.gradient, in: Capsule())
                            .padding(8)
                    }

                    if hovered {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "play.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                                    .shadow(radius: 4)
                                    .padding(8)
                            }
                        }
                        .transition(.opacity)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(album.title.isEmpty ? "未命名专辑" : album.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        if let subtitleOverride, !subtitleOverride.isEmpty {
                            Text(subtitleOverride)
                                .lineLimit(1)
                        } else if !album.artist.isEmpty {
                            Text(album.artist)
                                .lineLimit(1)
                        } else if album.total > 0 {
                            Text("共 \(album.total) 集")
                        }
                        if let count = TimeFormatter.playCountText(stats?.playCount) {
                            Text("· \(count)")
                                .lineLimit(1)
                        }
                        if let score = stats?.score, score > 0 {
                            Text(String(format: "· %.1f分", score))
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over in
            withAnimation(.easeOut(duration: 0.18)) {
                hovered = over
            }
        }
    }
}

/// 精致胶囊选择标签（用于频道、二级分类与 100 集分段）
struct PillChip: View {
    let title: String
    let selected: Bool
    var accent: Color = .accentColor
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? .white : .primary.opacity(hovered ? 0.95 : 0.78))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    if selected {
                        Capsule().fill(accent.gradient)
                    } else {
                        Capsule().fill(Color.primary.opacity(hovered ? 0.09 : 0.055))
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// 细腻跟手的原生感可拖拽音频进度条
struct PlaybackProgressBar: View {
    @Bindable var clock: PlaybackClock
    var accent: Color = .accentColor
    var height: CGFloat = 5
    let onCommitSeek: (Double) -> Void

    @State private var hovered = false
    @State private var dragProgress: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let displayProgress = dragProgress ?? clock.progress
            let bufferedProgress = clock.duration > 0 ? min(max(clock.bufferedTime / clock.duration, 0), 1) : 0
            let barHeight = (hovered || dragProgress != nil) ? height + 2 : height

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.11))
                    .frame(height: barHeight)

                if bufferedProgress > 0 {
                    Capsule()
                        .fill(Color.primary.opacity(0.14))
                        .frame(width: width * bufferedProgress, height: barHeight)
                }

                Capsule()
                    .fill(accent.gradient)
                    .frame(width: max(0, width * displayProgress), height: barHeight)

                if hovered || dragProgress != nil {
                    Circle()
                        .fill(.white)
                        .frame(width: barHeight + 5, height: barHeight + 5)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .offset(x: min(max(0, width * displayProgress - (barHeight + 5) / 2), width - (barHeight + 5)))
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard clock.duration > 0 else { return }
                        clock.isScrubbing = true
                        let p = min(max(value.location.x / width, 0), 1)
                        dragProgress = p
                        clock.currentTime = p * clock.duration
                    }
                    .onEnded { value in
                        guard clock.duration > 0 else {
                            clock.isScrubbing = false
                            dragProgress = nil
                            return
                        }
                        let p = min(max(value.location.x / width, 0), 1)
                        let target = p * clock.duration
                        dragProgress = nil
                        clock.isScrubbing = false
                        onCommitSeek(target)
                    }
            )
            .onHover { over in
                withAnimation(.easeOut(duration: 0.14)) {
                    hovered = over
                }
            }
        }
        .frame(height: 16)
    }
}

/// 轻盈顶部悬浮提示条
struct ToastBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(2)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
    }
}

/// 正在播放的动态声波小图标
struct PlayingBarsIndicator: View {
    let isPlaying: Bool
    var color: Color = .accentColor

    var body: some View {
        Image(systemName: isPlaying ? "waveform" : "pause.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .symbolEffect(.variableColor.iterative, isActive: isPlaying)
    }
}

/// 统一的空态或错误态占位卡片
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary.opacity(0.7))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
