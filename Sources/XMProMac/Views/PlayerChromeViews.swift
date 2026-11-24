import SwiftUI
import XMProCore

/// 底部悬浮毛玻璃播控条（苹果播客美学 + 柔和封面动态氛围光晕）
struct FloatingPlayerBar: View {
    @Bindable var store: AppStore
    @Bindable var clock: PlaybackClock

    @State private var showSpeedPopover = false
    @State private var showTimerPopover = false

    var body: some View {
        HStack(spacing: 16) {
            // 左侧：封面与标题（点击展开沉浸播放抽屉）
            Button {
                if store.currentTrack != nil {
                    store.showPlayerDrawer = true
                }
            } label: {
                HStack(spacing: 11) {
                    ArtworkImageView(
                        urlString: store.currentTrack?.coverUrl,
                        cornerRadius: 9,
                        shadowRadius: 4
                    )
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack(spacing: 6) {
                            Text(store.currentTrack?.title ?? "未在播放")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if !store.playingQuality.isEmpty {
                                Text(QualityLabel.shortBadge(for: store.playingQuality))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(store.ambientColor)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(store.ambientColor.opacity(0.15), in: Capsule())
                            }
                        }

                        Text(subtitleText)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 180, maxWidth: 260, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("打开沉浸播放与待播队列")

            // 中间：播控按键与顺滑进度条
            VStack(spacing: 4) {
                HStack(spacing: 16) {
                    Button(action: store.playPrevious) {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("上一集")

                    Button { store.skip(by: -15) } label: {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("快退 15 秒")

                    Button(action: store.togglePlayPause) {
                        ZStack {
                            Circle()
                                .fill(store.ambientColor.gradient)
                                .frame(width: 34, height: 34)
                                .shadow(color: store.ambientColor.opacity(0.35), radius: 6, y: 2)

                            if store.isResolving || store.isBuffering {
                                ProgressView()
                                    .controlSize(.small)
                                    .colorScheme(.dark)
                            } else {
                                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .offset(x: store.isPlaying ? 0 : 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(store.isPlaying ? "暂停 (空格)" : "播放 (空格)")

                    Button { store.skip(by: 15) } label: {
                        Image(systemName: "goforward.15")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("快进 15 秒")

                    Button(action: store.playNext) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("下一集")
                }

                HStack(spacing: 8) {
                    Text(TimeFormatter.mmss(clock.currentTime))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)

                    PlaybackProgressBar(
                        clock: clock,
                        accent: store.ambientColor,
                        height: 4
                    ) { target in
                        store.seek(to: target)
                    }

                    Text(TimeFormatter.mmss(clock.duration))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)

            // 右侧：倍速、定时、音量与队列抽屉
            HStack(spacing: 11) {
                Button {
                    showSpeedPopover.toggle()
                } label: {
                    Text(String(format: "%.2g×", store.preferences.speed))
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(store.preferences.speed == 1.0 ? .secondary : store.ambientColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSpeedPopover, arrowEdge: .top) {
                    SpeedPopoverView(store: store)
                }
                .help("播放倍速")

                Button {
                    showTimerPopover.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: store.sleepTimerOption == .off ? "moon" : "moon.fill")
                            .font(.system(size: 12.5))
                        if store.sleepRemainingSeconds > 0 {
                            Text(TimeFormatter.mmss(Double(store.sleepRemainingSeconds)))
                                .font(.system(size: 10.5, design: .monospaced))
                        }
                    }
                    .foregroundStyle(store.sleepTimerOption == .off ? .secondary : store.ambientColor)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showTimerPopover, arrowEdge: .top) {
                    SleepTimerPopoverView(store: store)
                }
                .help("定时关闭")

                HStack(spacing: 5) {
                    Image(systemName: volumeIcon)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Slider(value: $store.preferences.volume, in: 0...1)
                        .controlSize(.mini)
                        .frame(width: 68)
                }

                Button {
                    store.showPlayerDrawer = true
                } label: {
                    Image(systemName: "list.bullet.below.rectangle")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("待播队列与播放设置")
            }
            .frame(minWidth: 190, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                store.ambientColor.opacity(0.11),
                                store.ambientColor.opacity(0.03),
                                Color.clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.16), radius: 18, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private var subtitleText: String {
        guard let track = store.currentTrack else {
            return "挑选一本喜欢的有声书开始聆听"
        }
        let parts = [track.album, track.artist].filter { !$0.isEmpty }
        return parts.isEmpty ? "喜马拉雅" : parts.joined(separator: " · ")
    }

    private var volumeIcon: String {
        if store.preferences.volume <= 0.01 { return "speaker.slash.fill" }
        if store.preferences.volume < 0.5 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }
}

/// 倍速调节气泡
struct SpeedPopoverView: View {
    @Bindable var store: AppStore
    private let presets: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("播放倍速")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(String(format: "%.2f×", store.preferences.speed))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
            }

            Slider(
                value: Binding(
                    get: { store.preferences.speed },
                    set: { store.setSpeed($0) }
                ),
                in: 0.5...3.0,
                step: 0.05
            )

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(presets, id: \.self) { val in
                    let active = abs(store.preferences.speed - val) < 0.01
                    Button(String(format: "%.2g×", val)) {
                        store.setSpeed(val)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: active ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(active ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        active ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                }
            }
        }
        .padding(14)
        .frame(width: 248)
    }
}

/// 定时关闭气泡
struct SleepTimerPopoverView: View {
    @Bindable var store: AppStore

    private let options: [SleepTimerOption] = [
        .off, .endOfTrack, .minutes(15), .minutes(30), .minutes(45), .minutes(60),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("定时关闭")
                .font(.system(size: 13, weight: .semibold))
                .padding(.bottom, 2)

            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = store.sleepTimerOption == option
                Button {
                    store.setSleepTimer(option)
                } label: {
                    HStack {
                        Text(option.label)
                            .font(.system(size: 12.5))
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        selected ? Color.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 180)
    }
}

/// 沉浸式播放详情、待播队列与精细设置抽屉 Sheet
struct PlayerDrawerSheet: View {
    @Bindable var store: AppStore
    @Bindable var clock: PlaybackClock
    @Environment(\.dismiss) private var dismiss

    @State private var rightTab: Int = 0 // 0: 待播队列, 1: 音频与跳过设置

    var body: some View {
        ZStack {
            // 柔和封面氛围光背景
            LinearGradient(
                colors: [
                    store.ambientColor.opacity(0.18),
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .windowBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("正在播放")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 10)

                HStack(spacing: 24) {
                    leftArtworkStage
                        .frame(width: 320)

                    Divider().opacity(0.45)

                    rightControlPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
        }
        .frame(width: 780, height: 520)
    }

    private var leftArtworkStage: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 4)

            ArtworkImageView(
                urlString: store.currentTrack?.coverUrl,
                cornerRadius: 20,
                shadowRadius: store.isPlaying ? 22 : 10
            )
            .frame(width: 224, height: 224)
            .scaleEffect(store.isPlaying ? 1.0 : 0.94)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: store.isPlaying)

            VStack(spacing: 5) {
                Text(store.currentTrack?.title ?? "未在播放")
                    .font(.system(size: 16.5, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if let track = store.currentTrack {
                    Button {
                        if !track.albumKey.isEmpty {
                            dismiss()
                            store.openAlbum(track.albumKey)
                        }
                    } label: {
                        Text([track.album, track.artist].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 4) {
                PlaybackProgressBar(clock: clock, accent: store.ambientColor, height: 5) { target in
                    store.seek(to: target)
                }
                HStack {
                    Text(TimeFormatter.mmss(clock.currentTime))
                    Spacer()
                    Text("-\(TimeFormatter.mmss(clock.remainingTime))")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 22) {
                Button(action: store.playPrevious) {
                    Image(systemName: "backward.end.fill").font(.system(size: 16))
                }
                .buttonStyle(.plain)

                Button { store.skip(by: -15) } label: {
                    Image(systemName: "gobackward.15").font(.system(size: 18))
                }
                .buttonStyle(.plain)

                Button(action: store.togglePlayPause) {
                    ZStack {
                        Circle()
                            .fill(store.ambientColor.gradient)
                            .frame(width: 48, height: 48)
                            .shadow(color: store.ambientColor.opacity(0.35), radius: 10, y: 3)
                        Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: store.isPlaying ? 0 : 1.5)
                    }
                }
                .buttonStyle(.plain)

                Button { store.skip(by: 15) } label: {
                    Image(systemName: "goforward.15").font(.system(size: 18))
                }
                .buttonStyle(.plain)

                Button(action: store.playNext) {
                    Image(systemName: "forward.end.fill").font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }

            if let track = store.currentTrack {
                let isFav = store.favoriteTrackIds.contains(track.id)
                HStack(spacing: 14) {
                    Button {
                        store.toggleFavorite(track: track)
                    } label: {
                        Label(isFav ? "已收藏" : "收藏本集", systemImage: isFav ? "heart.fill" : "heart")
                            .font(.system(size: 12))
                            .foregroundStyle(isFav ? .pink : .secondary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if !store.playingQuality.isEmpty {
                        Text(QualityLabel.title(for: store.playingQuality))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 4)
        }
    }

    private var rightControlPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $rightTab) {
                Text("待播队列 (\(store.queue.count))").tag(0)
                Text("音质与跳过头尾").tag(1)
            }
            .pickerStyle(.segmented)

            if rightTab == 0 {
                queuePanel
            } else {
                playbackSettingsPanel
            }
        }
    }

    private var queuePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.queueSegments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        PillChip(title: "全部", selected: store.queueSegment == nil, accent: store.ambientColor) {
                            store.setQueueSegment(nil)
                        }
                        ForEach(store.queueSegments) { seg in
                            PillChip(title: seg.label, selected: store.queueSegment == seg, accent: store.ambientColor) {
                                store.setQueueSegment(seg)
                            }
                        }
                    }
                }
            }

            if store.queue.isEmpty {
                EmptyStateView(icon: "text.line.first.and.arrowtriangle.forward", title: "队列为空", subtitle: "点击任意声音后会自动载入所属专辑队列")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(Array(store.queue.enumerated()), id: \.element.id) { idx, item in
                                let active = item.id == store.currentTrack?.id
                                HStack(spacing: 10) {
                                    if active {
                                        PlayingBarsIndicator(isPlaying: store.isPlaying, color: store.ambientColor)
                                            .frame(width: 24)
                                    } else {
                                        Text("\(item.displayOrder ?? (idx + 1))")
                                            .font(.system(size: 11.5, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 24)
                                    }
                                    Text(item.title)
                                        .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                                        .foregroundStyle(active ? store.ambientColor : .primary)
                                        .lineLimit(1)
                                    Spacer()
                                    if item.duration > 0 {
                                        Text(TimeFormatter.mmss(item.duration))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .id(item.id)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    active ? store.ambientColor.opacity(0.12) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    store.playQueue(store.queue, index: idx, fullSource: store.queueAll, segment: store.queueSegment)
                                }
                            }
                        }
                    }
                    .onAppear {
                        if let id = store.currentTrack?.id {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var playbackSettingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 音质设置
                VStack(alignment: .leading, spacing: 8) {
                    Text("音频清晰度")
                        .font(.system(size: 13, weight: .semibold))
                    let allQualities = ["auto"] + xmlyQualities
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], spacing: 8) {
                        ForEach(allQualities, id: \.self) { q in
                            let selected = store.preferences.quality == q
                            Button {
                                store.setQuality(q)
                            } label: {
                                Text(QualityLabel.title(for: q))
                                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? .white : .primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(
                                        selected ? AnyShapeStyle(store.ambientColor.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider().opacity(0.45)

                // 跳过头尾设置
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("启用跳过片头片尾", isOn: $store.preferences.skipTrimEnabled)
                        .font(.system(size: 13, weight: .semibold))

                    if store.preferences.skipTrimEnabled {
                        Picker("检测方式", selection: $store.preferences.skipTrimMode) {
                            ForEach(SkipTrimMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if store.preferences.skipTrimMode == .smart {
                            Text("后台自动分析首尾空白静音片段，无需手动调参数，不影响秒速起播。")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("跳过片头比例")
                                    Spacer()
                                    Text(String(format: "%.1f%%", Double(store.preferences.introSkipPermille) / 10.0))
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Slider(
                                    value: Binding(
                                        get: { Double(store.preferences.introSkipPermille) },
                                        set: { store.preferences.introSkipPermille = Int($0.rounded()) }
                                    ),
                                    in: 0...250,
                                    step: 5
                                )

                                HStack {
                                    Text("跳过片尾比例")
                                    Spacer()
                                    Text(String(format: "%.1f%%", Double(store.preferences.outroSkipPermille) / 10.0))
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Slider(
                                    value: Binding(
                                        get: { Double(store.preferences.outroSkipPermille) },
                                        set: { store.preferences.outroSkipPermille = Int($0.rounded()) }
                                    ),
                                    in: 0...250,
                                    step: 5
                                )
                            }
                            .font(.system(size: 12.5))
                        }
                    }
                }

                Divider().opacity(0.45)

                // 倍速快捷调整
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("播放倍速")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(String(format: "%.2f×", store.preferences.speed))
                            .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(store.ambientColor)
                    }
                    Slider(
                        value: Binding(
                            get: { store.preferences.speed },
                            set: { store.setSpeed($0) }
                        ),
                        in: 0.5...3.0,
                        step: 0.05
                    )
                }
            }
            .padding(.top, 4)
        }
    }
}
