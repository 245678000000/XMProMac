import CryptoKit
import Foundation

/// 喜马拉雅账号凭据：`<uid>&<token>` 与绑定设备 ID
/// 注意：严禁在日志或控制台输出真实令牌，description 已脱敏
public struct Credentials: Equatable, Hashable, Codable, CustomStringConvertible, Sendable {
    public let token: String
    public let deviceId: String

    private static let tokenRegex = try! NSRegularExpression(pattern: "^[1-9][0-9]{0,19}&[A-Za-z0-9._~+/=\\-]{1,8192}$")
    private static let deviceRegex = try! NSRegularExpression(pattern: "^[A-Za-z0-9_.:\\-]{1,128}$")
    private static let cookiePairRegex = try! NSRegularExpression(
        pattern: #"(?:^|[;:\s"'`])1&_(token|device)\s*=\s*([^;\s"'`\\,]+)"#
    )

    public init(rawToken: String, rawDeviceId: String) throws {
        var cleanedToken = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedToken.hasPrefix("1&_token=") {
            cleanedToken = String(cleanedToken.dropFirst("1&_token=".count))
        }
        let cleanedDevice = rawDeviceId.trimmingCharacters(in: .whitespacesAndNewlines)

        let tokenRange = NSRange(cleanedToken.startIndex..<cleanedToken.endIndex, in: cleanedToken)
        guard Self.tokenRegex.firstMatch(in: cleanedToken, range: tokenRange) != nil else {
            throw XmlyException(
                code: "invalid_credentials",
                message: "账号凭据必须是数字 UID 与登录令牌",
                definitive: true
            )
        }
        let deviceRange = NSRange(cleanedDevice.startIndex..<cleanedDevice.endIndex, in: cleanedDevice)
        guard Self.deviceRegex.firstMatch(in: cleanedDevice, range: deviceRange) != nil else {
            throw XmlyException(
                code: "invalid_credentials",
                message: "请填写原设备 ID",
                definitive: true
            )
        }
        self.token = cleanedToken
        self.deviceId = cleanedDevice
    }

    public var uid: String {
        String(token.split(separator: "&", maxSplits: 1).first ?? "")
    }

    public var tokenSecret: String {
        let parts = token.split(separator: "&", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : ""
    }

    /// 稳定的账号唯一键（用于存储与听时账本）
    public var identity: String {
        Self.sha256Hex("\(uid)|\(deviceId)")
    }

    /// 覆盖令牌版本和客户端信息的缓存键
    public var cacheIdentity: String {
        Self.sha256Hex("\(token)|android&\(deviceId)&3.4.10")
    }

    /// 极速版接口标准 Cookie
    public var cookie: String {
        "1&_token=\(token); 1&_device=android&\(deviceId)&3.4.10; channel=and-f5; impl=com.ximalaya.ting.lite; appid=1463"
    }

    /// 主站接口标准 Cookie
    public var mainAppCookie: String {
        "1&_token=\(token); 1&_device=android&\(deviceId)&9.5.1; channel=and-d10; impl=com.ximalaya.ting.android; appid=1463"
    }

    public var description: String { "Credentials(redacted)" }

    /// 兼容裸 Cookie 字符串、JSON 对象或嵌套 `xmly`/`config` 格式的导入解析
    public static func parse(_ rawInput: String) throws -> Credentials {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw XmlyException(code: "invalid_credentials", message: "请输入 Cookie 或登录配置", definitive: true)
        }

        let sourceMap: [String: Any]
        if trimmed.hasPrefix("{") {
            guard let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw XmlyException(code: "invalid_credentials", message: "登录信息 JSON 格式错误", definitive: true)
            }
            sourceMap = obj
        } else {
            sourceMap = ["cookie": trimmed]
        }

        return try parse(dictionary: sourceMap)
    }

    public static func parse(dictionary source: [String: Any]) throws -> Credentials {
        var map = source
        if let nested = map["xmly"] as? [String: Any] {
            map = nested
        }
        if let nested = map["config"] as? [String: Any] {
            map = nested
        }
        let headers = map["headers"] as? [String: Any] ?? [:]
        let cookieValue = (headers["cookie"] ?? headers["Cookie"] ?? map["cookie"]) as? String

        var token = map["token"] as? String
        var device = (map["device_id"] ?? map["deviceId"]) as? String

        if let cookie = cookieValue {
            var parts: [String: String] = [:]
            let nsRange = NSRange(cookie.startIndex..<cookie.endIndex, in: cookie)
            for match in cookiePairRegex.matches(in: cookie, range: nsRange) {
                guard let keyRange = Range(match.range(at: 1), in: cookie),
                      let valRange = Range(match.range(at: 2), in: cookie) else { continue }
                let key = "1&_\(cookie[keyRange])"
                let val = String(cookie[valRange])
                if let existing = parts[key], existing != val {
                    throw XmlyException(
                        code: "invalid_credentials",
                        message: "包含多组登录信息，请只保留一个账号的 Cookie",
                        definitive: true
                    )
                }
                parts[key] = val
            }
            if token == nil {
                token = parts["1&_token"]
            }
            if let devRaw = parts["1&_device"] {
                let fields = devRaw.split(separator: "&", omittingEmptySubsequences: false)
                if fields.count > 1, device == nil {
                    device = String(fields[1])
                }
            }
        }

        guard let finalToken = token, let finalDevice = device else {
            throw XmlyException(code: "invalid_credentials", message: "缺少账号令牌或原设备 ID", definitive: true)
        }
        return try Credentials(rawToken: finalToken, rawDeviceId: finalDevice)
    }

    private static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
