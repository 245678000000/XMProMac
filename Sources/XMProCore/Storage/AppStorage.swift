import CryptoKit
import Foundation

/// 跳过头尾模式（智能静音检测 / 按全集比例手动裁剪）
public enum SkipTrimMode: String, Codable, CaseIterable, Sendable {
    case smart
    case manual

    public var displayName: String {
        switch self {
        case .smart: return "智能静音跳过"
        case .manual: return "手动按比例裁剪"
        }
    }
}

/// 持久化应用偏好配置
public struct AppPreferences: Codable, Equatable, Sendable {
    public var speed: Double
    public var quality: String
    public var volume: Double
    public var autoClaimRewards: Bool
    public var skipTrimEnabled: Bool
    public var skipTrimMode: SkipTrimMode
    /// 片头跳过千分比（0..250，默认 20 即 2%）
    public var introSkipPermille: Int
    /// 片尾跳过千分比（0..250，默认 20 即 2%）
    public var outroSkipPermille: Int
    /// 关闭主窗口时是否隐藏到菜单栏继续后台播放
    public var keepRunningInMenuBar: Bool
    /// 稳定的设备安装 ID，确保重新登录后仍保持设备听时绑定
    public var installDeviceId: String

    public init(
        speed: Double = 1.0,
        quality: String = "auto",
        volume: Double = 1.0,
        autoClaimRewards: Bool = true,
        skipTrimEnabled: Bool = false,
        skipTrimMode: SkipTrimMode = .smart,
        introSkipPermille: Int = 20,
        outroSkipPermille: Int = 20,
        keepRunningInMenuBar: Bool = true,
        installDeviceId: String = UUID().uuidString.lowercased()
    ) {
        self.speed = Self.normalizeSpeed(speed)
        self.quality = quality
        self.volume = min(max(volume, 0.0), 1.0)
        self.autoClaimRewards = autoClaimRewards
        self.skipTrimEnabled = skipTrimEnabled
        self.skipTrimMode = skipTrimMode
        self.introSkipPermille = min(max(introSkipPermille, 0), 250)
        self.outroSkipPermille = min(max(outroSkipPermille, 0), 250)
        self.keepRunningInMenuBar = keepRunningInMenuBar
        self.installDeviceId = installDeviceId
    }

    public static func normalizeSpeed(_ raw: Double) -> Double {
        guard raw.isFinite else { return 1.0 }
        let clamped = min(max(raw, 0.5), 3.0)
        let snapped = (clamped / 0.05).rounded() * 0.05
        return min(max(snapped, 0.5), 3.0)
    }
}

/// 本地持久化存储（安全加密凭据 + 偏好设置 + 本地最近播放进度 + 用户资料缓存）
public final class AppStorage: @unchecked Sendable {
    private let baseDirectory: URL
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(baseDirectory: URL? = nil) {
        if let dir = baseDirectory {
            self.baseDirectory = dir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            self.baseDirectory = appSupport.appendingPathComponent("XMProMac", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.baseDirectory, withIntermediateDirectories: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    // MARK: - 凭据安全存储（AES-GCM 密封 + 0600 权限，避免 ad-hoc 签名频繁弹 Keychain 密码框）

    private var keyFileURL: URL { baseDirectory.appendingPathComponent(".seal.key") }
    private var credentialsFileURL: URL { baseDirectory.appendingPathComponent("credentials.sealed") }
    private var preferencesFileURL: URL { baseDirectory.appendingPathComponent("preferences.json") }
    private var profileFileURL: URL { baseDirectory.appendingPathComponent("profile.json") }
    private var positionsFileURL: URL { baseDirectory.appendingPathComponent("positions.json") }

    public func loadCredentials() -> Credentials? {
        lock.lock()
        defer { lock.unlock() }
        guard let sealed = try? Data(contentsOf: credentialsFileURL),
              let key = loadOrCreateSealKey(),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let plain = try? AES.GCM.open(box, using: key),
              let creds = try? decoder.decode(Credentials.self, from: plain) else {
            return nil
        }
        return creds
    }

    public func saveCredentials(_ credentials: Credentials?) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let credentials else {
            try? FileManager.default.removeItem(at: credentialsFileURL)
            try? FileManager.default.removeItem(at: profileFileURL)
            return
        }
        guard let key = loadOrCreateSealKey() else {
            throw XmlyException(code: "storage_error", message: "无法创建本地加密密钥")
        }
        let plain = try encoder.encode(credentials)
        let sealed = try AES.GCM.seal(plain, using: key)
        guard let combined = sealed.combined else {
            throw XmlyException(code: "storage_error", message: "凭据加密失败")
        }
        try writePrivateFile(combined, to: credentialsFileURL)
    }

    // MARK: - 偏好配置

    public func loadPreferences() -> AppPreferences {
        lock.lock()
        defer { lock.unlock() }
        if let data = try? Data(contentsOf: preferencesFileURL),
           let prefs = try? decoder.decode(AppPreferences.self, from: data) {
            return prefs
        }
        let fresh = AppPreferences()
        if let data = try? encoder.encode(fresh) {
            try? data.write(to: preferencesFileURL, options: .atomic)
        }
        return fresh
    }

    public func savePreferences(_ preferences: AppPreferences) {
        lock.lock()
        defer { lock.unlock() }
        if let data = try? encoder.encode(preferences) {
            try? data.write(to: preferencesFileURL, options: .atomic)
        }
    }

    // MARK: - 用户资料缓存（仅非敏感信息）

    public func loadProfile() -> UserProfile? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: profileFileURL) else { return nil }
        return try? decoder.decode(UserProfile.self, from: data)
    }

    public func saveProfile(_ profile: UserProfile?) {
        lock.lock()
        defer { lock.unlock() }
        guard let profile else {
            try? FileManager.default.removeItem(at: profileFileURL)
            return
        }
        if let data = try? encoder.encode(profile) {
            try? data.write(to: profileFileURL, options: .atomic)
        }
    }

    // MARK: - 本机专辑最近播放进度（每专辑保留最近 5 条，最多 80 张专辑）

    public func loadPositions() -> [String: [PlayPosition]] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: positionsFileURL),
              let map = try? decoder.decode([String: [PlayPosition]].self, from: data) else {
            return [:]
        }
        return map
    }

    public func rememberPosition(track: Track, positionSeconds: Double) -> [String: [PlayPosition]] {
        lock.lock()
        defer { lock.unlock() }
        var map: [String: [PlayPosition]] = {
            guard let data = try? Data(contentsOf: positionsFileURL),
                  let decoded = try? decoder.decode([String: [PlayPosition]].self, from: data) else {
                return [:]
            }
            return decoded
        }()
        let key = track.albumKey.isEmpty ? track.id : track.albumKey
        var list = map[key] ?? []
        list.removeAll { $0.track.id == track.id }
        let entry = PlayPosition(
            track: track,
            positionSeconds: max(0, positionSeconds),
            atMillis: Int64(Date().timeIntervalSince1970 * 1000)
        )
        list.insert(entry, at: 0)
        if list.count > 5 { list = Array(list.prefix(5)) }
        map[key] = list

        if map.count > 80 {
            let sortedKeys = map.keys.sorted { lhs, rhs in
                (map[lhs]?.first?.atMillis ?? 0) > (map[rhs]?.first?.atMillis ?? 0)
            }
            let keep = Set(sortedKeys.prefix(80))
            map = map.filter { keep.contains($0.key) }
        }
        if let data = try? encoder.encode(map) {
            try? data.write(to: positionsFileURL, options: .atomic)
        }
        return map
    }

    // MARK: - 内部加密文件工具

    private func loadOrCreateSealKey() -> SymmetricKey? {
        if let existing = try? Data(contentsOf: keyFileURL), existing.count == 32 {
            return SymmetricKey(data: existing)
        }
        let raw = Data(XmlyCrypto.randomBytes(count: 32))
        do {
            try writePrivateFile(raw, to: keyFileURL)
            return SymmetricKey(data: raw)
        } catch {
            return nil
        }
    }

    private func writePrivateFile(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: url.path)
    }
}
