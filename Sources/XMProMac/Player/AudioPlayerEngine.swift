import AVFoundation
import Foundation

/// 远程音频首尾静音边界分析器（用于智能跳过头尾模式，异步后台执行不阻塞起播）
enum SmartSilenceAnalyzer {
    struct TrimPoints: Sendable {
        let introEndSeconds: Double
        let outroStartSeconds: Double?
    }

    /// 对远程流首尾进行轻量静音检测（仅在格式支持时触发，失败安全返回 nil）
    static func analyze(url: URL, duration: Double) async -> TrimPoints? {
        guard duration > 45 else { return nil }
        let asset = AVURLAsset(url: url)
        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }

        let introEnd = await detectLeadingSilenceEnd(asset: asset, track: audioTrack, maxWindow: min(25.0, duration * 0.15))
        let outroStart = await detectTrailingSilenceStart(asset: asset, track: audioTrack, duration: duration, window: min(25.0, duration * 0.15))
        if introEnd <= 0.4 && outroStart == nil {
            return nil
        }
        return TrimPoints(introEndSeconds: introEnd, outroStartSeconds: outroStart)
    }

    private static func detectLeadingSilenceEnd(
        asset: AVAsset,
        track: AVAssetTrack,
        maxWindow: Double
    ) async -> Double {
        let range = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: maxWindow, preferredTimescale: 600)
        )
        guard let rmsFrames = readRMSFrames(asset: asset, track: track, timeRange: range) else {
            return 0
        }
        // 阈值约 -36dB (线性振幅 ~0.016)，连续非静音超过 0.3s 即判定正片开始
        let threshold: Float = 0.016
        var consecutiveVoice = 0
        for frame in rmsFrames {
            if frame.rms >= threshold {
                consecutiveVoice += 1
                if consecutiveVoice >= 3 {
                    return max(0, frame.time - 0.25)
                }
            } else {
                consecutiveVoice = 0
            }
        }
        return 0
    }

    private static func detectTrailingSilenceStart(
        asset: AVAsset,
        track: AVAssetTrack,
        duration: Double,
        window: Double
    ) async -> Double? {
        let start = max(0, duration - window)
        let range = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: window, preferredTimescale: 600)
        )
        guard let rmsFrames = readRMSFrames(asset: asset, track: track, timeRange: range),
              !rmsFrames.isEmpty else {
            return nil
        }
        let threshold: Float = 0.016
        for frame in rmsFrames.reversed() {
            if frame.rms >= threshold {
                let tailGap = duration - frame.time
                return tailGap >= 2.5 ? min(duration - 0.5, frame.time + 0.4) : nil
            }
        }
        return nil
    }

    private struct RMSFrame {
        let time: Double
        let rms: Float
    }

    private static func readRMSFrames(
        asset: AVAsset,
        track: AVAssetTrack,
        timeRange: CMTimeRange
    ) -> [RMSFrame]? {
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        reader.timeRange = timeRange
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 8000,
            AVNumberOfChannelsKey: 1,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        var frames: [RMSFrame] = []
        let chunkSamples = 800 // 0.1 秒每帧
        var accumSquare: Double = 0
        var accumCount = 0
        var currentTime = timeRange.start.seconds

        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &dataPointer
            ) == noErr, let ptr = dataPointer else { continue }

            let sampleCount = length / MemoryLayout<Int16>.size
            let samples = ptr.withMemoryRebound(to: Int16.self, capacity: sampleCount) { $0 }
            for i in 0..<sampleCount {
                let normalized = Double(samples[i]) / 32768.0
                accumSquare += normalized * normalized
                accumCount += 1
                if accumCount >= chunkSamples {
                    let rms = Float(sqrt(accumSquare / Double(accumCount)))
                    frames.append(RMSFrame(time: currentTime, rms: rms))
                    currentTime += 0.1
                    accumSquare = 0
                    accumCount = 0
                }
            }
        }
        reader.cancelReading()
        return frames
    }
}

/// 原生 macOS 音频播放引擎（基于 AVFoundation AVPlayer）
@MainActor
public final class AudioPlayerEngine {
    public let clock = PlaybackClock()

    public private(set) var isPlaying: Bool = false
    public private(set) var isBuffering: Bool = false
    public private(set) var currentMediaId: String?

    public var rate: Double = 1.0 {
        didSet {
            if isPlaying {
                player.rate = Float(rate)
            }
        }
    }

    public var volume: Double = 1.0 {
        didSet {
            player.volume = Float(min(max(volume, 0.0), 1.0))
        }
    }

    public var onStateChanged: ((_ isPlaying: Bool, _ isBuffering: Bool) -> Void)?
    public var onTrackEnded: ((_ mediaId: String) -> Void)?
    public var onFailure: ((_ mediaId: String, _ message: String, _ position: Double) -> Void)?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var activeToken: Int = 0

    public init() {
        player.automaticallyWaitsToMinimizeStalling = true
        installPeriodicObserver()
        installPlayerObservers()
    }

    deinit {
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let failObserver {
            NotificationCenter.default.removeObserver(failObserver)
        }
    }

    /// 启动播放指定 HTTPS 音频直链
    public func start(
        urlString: String,
        mediaId: String,
        expectedDuration: Double,
        startPosition: Double,
        rate: Double,
        volume: Double
    ) {
        guard let url = URL(string: urlString) else {
            onFailure?(mediaId, "音频链接格式无效", startPosition)
            return
        }
        activeToken += 1
        let token = activeToken
        currentMediaId = mediaId
        self.rate = rate
        self.volume = volume

        detachItemObservers()
        clock.reset(duration: expectedDuration, position: startPosition)

        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": "ting_3.4.10.3(Android,30)",
                "Accept": "*/*",
            ],
        ])
        let item = AVPlayerItem(asset: asset)
        // 对人声与有声书采用 timeDomain 变速算法，倍速清晰自然无回声
        item.audioTimePitchAlgorithm = .timeDomain

        attachItemObservers(item: item, mediaId: mediaId, token: token)
        player.replaceCurrentItem(with: item)
        player.volume = Float(min(max(volume, 0.0), 1.0))

        isBuffering = true
        isPlaying = true
        onStateChanged?(isPlaying, isBuffering)

        if startPosition > 0.5 {
            let target = CMTime(seconds: startPosition, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.activeToken == token else { return }
                    self.player.playImmediately(atRate: Float(self.rate))
                }
            }
        } else {
            player.playImmediately(atRate: Float(rate))
        }
    }

    public func play() {
        guard player.currentItem != nil else { return }
        player.playImmediately(atRate: Float(rate))
        isPlaying = true
        onStateChanged?(isPlaying, isBuffering)
    }

    public func pause() {
        player.pause()
        isPlaying = false
        isBuffering = false
        onStateChanged?(isPlaying, isBuffering)
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func stop() {
        activeToken += 1
        detachItemObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentMediaId = nil
        isPlaying = false
        isBuffering = false
        clock.reset()
        onStateChanged?(false, false)
    }

    public func seek(to seconds: Double) {
        guard player.currentItem != nil else { return }
        let clamped = max(0, clock.duration > 0 ? min(seconds, clock.duration) : seconds)
        clock.currentTime = clamped
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: CMTime(seconds: 0.2, preferredTimescale: 600), toleranceAfter: CMTime(seconds: 0.2, preferredTimescale: 600))
    }

    public func skip(by delta: Double) {
        seek(to: clock.currentTime + delta)
    }

    // MARK: - 内部监听

    private func installPeriodicObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.clock.isScrubbing else { return }
                let sec = time.seconds
                if sec.isFinite && sec >= 0 {
                    self.clock.currentTime = sec
                }
                if let item = self.player.currentItem {
                    let dur = item.duration.seconds
                    if dur.isFinite && dur > 0 {
                        self.clock.duration = dur
                    }
                    if let lastRange = item.loadedTimeRanges.last?.timeRangeValue {
                        let buffered = (lastRange.start + lastRange.duration).seconds
                        if buffered.isFinite && buffered >= 0 {
                            self.clock.bufferedTime = buffered
                        }
                    }
                }
            }
        }
    }

    private func installPlayerObservers() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.isPlaying = true
                    self.isBuffering = false
                case .waitingToPlayAtSpecifiedRate:
                    self.isPlaying = true
                    self.isBuffering = true
                case .paused:
                    self.isPlaying = false
                    self.isBuffering = false
                @unknown default:
                    break
                }
                self.onStateChanged?(self.isPlaying, self.isBuffering)
            }
        }
    }

    private func attachItemObservers(item: AVPlayerItem, mediaId: String, token: Int) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            Task { @MainActor in
                guard let self, self.activeToken == token else { return }
                if observed.status == .failed {
                    let msg = observed.error?.localizedDescription ?? "音频流加载失败"
                    self.isPlaying = false
                    self.isBuffering = false
                    self.onStateChanged?(false, false)
                    self.onFailure?(mediaId, "播放失败：\(msg)", self.clock.currentTime)
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.activeToken == token else { return }
                self.isPlaying = false
                self.isBuffering = false
                self.onStateChanged?(false, false)
                self.onTrackEnded?(mediaId)
            }
        }

        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self, self.activeToken == token else { return }
                let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self.isPlaying = false
                self.isBuffering = false
                self.onStateChanged?(false, false)
                self.onFailure?(mediaId, "播放中断：\(err?.localizedDescription ?? "网络异常")", self.clock.currentTime)
            }
        }
    }

    private func detachItemObservers() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failObserver {
            NotificationCenter.default.removeObserver(failObserver)
            self.failObserver = nil
        }
    }
}
