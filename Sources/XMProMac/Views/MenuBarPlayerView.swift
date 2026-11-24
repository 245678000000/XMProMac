import AppKit
import SwiftUI
import XMProCore

/// 常驻 macOS 菜单栏的精致迷你播控卡片（Popover）
struct MenuBarPlayerView: View {
    @Bindable var store: AppStore
    @Bindable var clock: PlaybackClock
    let onOpenMainWindow: () -> Void

    private let quickSpeeds: [Double] = [1.0, 1.25, 1.5, 2.0]

    var body: some View {
        VStack(spacing: 14) {
            // 顶部封面与标题
            HStack(spacing: 12) {
                ArtworkImageView(
                    urlString: store.currentTrack?.coverUrl,
                    cornerRadius: 11,
                    shadowRadius: 6
                )
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text(store.currentTrack?.title ?? "XMPro · 随时开听")
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(2)

                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button(action: onOpenMainWindow) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .help("打开主窗口")
            }

            // 进度条
            VStack(spacing: 3) {
                PlaybackProgressBar(clock: clock, accent: store.ambientColor, height: 4.5) { target in
                    store.seek(to: target)
                }
                HStack {
                    Text(TimeFormatter.mmss(clock.currentTime))
                    Spacer()
                    Text(TimeFormatter.mmss(clock.duration))
                }
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
            }

            // 5 键核心播控
            HStack(spacing: 20) {
                Button(action: store.playPrevious) {
                    Image(systemName: "backward.end.fill").font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button { store.skip(by: -15) } label: {
                    Image(systemName: "gobackward.15").font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button(action: store.togglePlayPause) {
                    ZStack {
                        Circle()
                            .fill(store.ambientColor.gradient)
                            .frame(width: 40, height: 40)
                            .shadow(color: store.ambientColor.opacity(0.32), radius: 8, y: 2)
                        if store.isResolving || store.isBuffering {
                            ProgressView().controlSize(.small).colorScheme(.dark)
                        } else {
                            Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: store.isPlaying ? 0 : 1)
                        }
                    }
                }
                .buttonStyle(.plain)

                Button { store.skip(by: 15) } label: {
                    Image(systemName: "goforward.15").font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button(action: store.playNext) {
                    Image(systemName: "forward.end.fill").font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            // 快捷倍速行
            HStack(spacing: 6) {
                Text("倍速")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                ForEach(quickSpeeds, id: \.self) { speed in
                    let active = abs(store.preferences.speed - speed) < 0.01
                    Button(String(format: "%.2g×", speed)) {
                        store.setSpeed(speed)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: active ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(active ? .white : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        active ? AnyShapeStyle(store.ambientColor.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)),
                        in: Capsule()
                    )
                }
            }

            Divider().opacity(0.45)

            // 底部状态与窗口操作
            HStack {
                if let quota = store.quota {
                    Label("听时 \(TimeFormatter.quotaDuration(quota.remainingSeconds))", systemImage: "hourglass")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                } else {
                    Text(store.signedIn ? "已登录" : "游客模式")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("打开主窗", action: onOpenMainWindow)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("退出") {
                    store.handleApplicationWillTerminate()
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            }
        }
        .padding(16)
        .frame(width: 332)
        .background {
            LinearGradient(
                colors: [
                    store.ambientColor.opacity(0.12),
                    Color.clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var subtitle: String {
        guard let track = store.currentTrack else {
            return "点击打开主窗挑选节目"
        }
        let parts = [track.album, track.artist].filter { !$0.isEmpty }
        return parts.isEmpty ? "喜马拉雅" : parts.joined(separator: " · ")
    }
}
