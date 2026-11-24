import Foundation

/// 跟踪本机时钟与喜马拉雅服务端时钟的偏差
/// 所有签名请求都依赖毫秒时间戳，偏差过大会触发服务端 `ret=-400` 拒绝
public final class ServerClock: @unchecked Sendable {
    public static let shared = ServerClock()

    private static let maxDriftMs: Int64 = 24 * 60 * 60 * 1000
    private let lock = NSLock()
    private var offsetMs: Int64 = 0

    private static let rfc1123Formatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEEE, dd-MMM-yy HH:mm:ss zzz",
            "EEE MMM d HH:mm:ss yyyy",
        ]
        return formats.map { format in
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = format
            return df
        }
    }()

    public init() {}

    /// 本进程是否已观测并校正过服务端时间
    public var synced: Bool {
        lock.lock()
        defer { lock.unlock() }
        return offsetMs != 0
    }

    /// 返回按服务端偏差校正后的当前毫秒时间戳
    public func nowMillis() -> Int64 {
        lock.lock()
        let offset = offsetMs
        lock.unlock()
        return Int64(Date().timeIntervalSince1970 * 1000) + offset
    }

    public func nowDate() -> Date {
        Date(timeIntervalSince1970: Double(nowMillis()) / 1000.0)
    }

    /// 观测原始时间戳（自动识别秒或毫秒）
    public func observeMillis(_ raw: Int64) {
        guard raw > 0 else { return }
        let millis = raw < 100_000_000_000 ? raw * 1000 : raw
        let localNow = Int64(Date().timeIntervalSince1970 * 1000)
        let drift = millis - localNow
        guard abs(drift) <= Self.maxDriftMs else { return }
        guard abs(drift) >= 1_000 else { return }
        lock.lock()
        offsetMs = drift
        lock.unlock()
    }

    /// 从 JSON 响应中的 `timestamp` 字段学习时间偏移
    public func observePayload(_ payload: [String: Any]) {
        if let num = payload["timestamp"] as? NSNumber {
            observeMillis(num.int64Value)
        } else if let str = payload["timestamp"] as? String, let val = Int64(str) {
            observeMillis(val)
        }
    }

    /// 从 HTTP 响应的 `Date` 头学习时间偏移
    public func observeDateHeader(_ value: String?) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return
        }
        lock.lock()
        let date = Self.rfc1123Formatters.lazy.compactMap { $0.date(from: value) }.first
        lock.unlock()
        if let date {
            observeMillis(Int64(date.timeIntervalSince1970 * 1000))
        }
    }
}
