import Foundation
import Observation

/// 独立的播放进度时钟对象
/// 与 AppStore 分离，避免每秒两次进度刷新触发首页或长列表重绘，保持极低 CPU 占用
@Observable
@MainActor
public final class PlaybackClock {
    public var currentTime: Double = 0
    public var duration: Double = 0
    public var bufferedTime: Double = 0
    public var isScrubbing: Bool = false

    public init() {}

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    public var remainingTime: Double {
        max(0, duration - currentTime)
    }

    public func reset(duration: Double = 0, position: Double = 0) {
        self.duration = max(0, duration)
        self.currentTime = min(max(0, position), max(0, duration))
        self.bufferedTime = 0
    }
}

/// 时间格式化辅助工具
public enum TimeFormatter {
    public static func mmss(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    public static func quotaDuration(_ seconds: Int) -> String {
        if seconds <= 0 { return "0 分钟" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 && minutes > 0 {
            return "\(hours) 小时 \(minutes) 分钟"
        } else if hours > 0 {
            return "\(hours) 小时"
        } else {
            return "\(max(1, minutes)) 分钟"
        }
    }

    public static func relativeDate(millis: Int64) -> String {
        guard millis > 0 else { return "" }
        let date = Date(timeIntervalSince1970: Double(millis) / 1000.0)
        let now = Date()
        let delta = now.timeIntervalSince(date)
        if delta < 60 { return "刚刚" }
        if delta < 3600 { return "\(Int(delta / 60)) 分钟前" }
        if delta < 86400 { return "\(Int(delta / 3600)) 小时前" }
        if delta < 7 * 86400 { return "\(Int(delta / 86400)) 天前" }
        let df = DateFormatter()
        df.dateFormat = "MM-dd"
        return df.string(from: date)
    }

    public static func playCountText(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        if count >= 100_000_000 {
            return String(format: "%.1f亿", Double(count) / 100_000_000.0)
        }
        if count >= 10_000 {
            return String(format: "%.1f万", Double(count) / 10_000.0)
        }
        return "\(count)"
    }
}
