import AppKit
import Foundation
import MediaPlayer

/// macOS 系统媒体中心桥接（控制中心、锁屏封面、键盘多媒体键与 AirPods 切集）
@MainActor
public final class NowPlayingBridge {
    public var onPlay: (() -> Void)?
    public var onPause: (() -> Void)?
    public var onTogglePlayPause: (() -> Void)?
    public var onNext: (() -> Void)?
    public var onPrevious: (() -> Void)?
    public var onSeek: ((Double) -> Void)?
    public var onSkipForward: ((Double) -> Void)?
    public var onSkipBackward: ((Double) -> Void)?

    private var installed = false
    private var lastArtworkUrl: String?
    private var cachedArtwork: MPMediaItemArtwork?

    public init() {}

    public func installCommands() {
        guard !installed else { return }
        installed = true
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPlay?() }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPause?() }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onTogglePlayPause?() }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onNext?() }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPrevious?() }
            return .success
        }

        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            Task { @MainActor in self?.onSkipForward?(interval) }
            return .success
        }

        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            Task { @MainActor in self?.onSkipBackward?(interval) }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let pos = posEvent.positionTime
            Task { @MainActor in self?.onSeek?(pos) }
            return .success
        }
    }

    public func update(
        title: String,
        artist: String,
        album: String,
        duration: Double,
        elapsed: Double,
        rate: Double,
        isPlaying: Bool,
        artworkUrl: String?
    ) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPMediaItemPropertyPlaybackDuration: max(0, duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, elapsed),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: rate,
        ]
        if let artworkUrl, artworkUrl == lastArtworkUrl, let art = cachedArtwork {
            info[MPMediaItemPropertyArtwork] = art
        }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused

        if let artworkUrl, !artworkUrl.isEmpty, artworkUrl != lastArtworkUrl {
            lastArtworkUrl = artworkUrl
            Task { @MainActor [weak self] in
                guard let self, let image = await ArtworkManager.shared.loadImage(from: artworkUrl) else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                guard self.lastArtworkUrl == artworkUrl else { return }
                self.cachedArtwork = artwork
                var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? info
                updated[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
            }
        }
    }

    public func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}
