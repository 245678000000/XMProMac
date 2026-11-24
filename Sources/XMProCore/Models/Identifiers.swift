import Foundation

/// 喜马拉雅通用标识符与媒体地址规范化工具
public enum XmlyIdentifiers {
    private static let idRegex = try! NSRegularExpression(pattern: "^(?:xmly:)?([1-9][0-9]{0,18})$")
    private static let digitsRegex = try! NSRegularExpression(pattern: "^[0-9]+$")
    private static let episodeRegex = try! NSRegularExpression(pattern: "第\\s*(\\d{1,6})\\s*[集话回期]")

    private static let coverKeys: [String] = [
        "coverLarge",
        "coverMiddle",
        "coverSmall",
        "cover_path",
        "album_cover_path",
        "cover_url",
        "albumImage",
    ]

    /// 将正整数或 `xmly:<正整数>` 规范化为纯数字 ID
    public static func xmlyIdentifier(_ value: String) throws -> String {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = idRegex.firstMatch(in: value, range: range),
              let captureRange = Range(match.range(at: 1), in: value) else {
            throw XmlyException(
                code: "invalid_id",
                message: "喜马拉雅 ID 必须是正整数或 xmly:正整数",
                definitive: true
            )
        }
        return String(value[captureRange])
    }

    /// 严格解析正整数（仅接受整数值或纯数字字符串）
    public static func xmlyPositive(_ value: Any?) -> Int? {
        guard let value else { return nil }
        let text: String
        if let str = value as? String {
            text = str
        } else if let num = value as? NSNumber {
            // 排除布尔值与小数
            if CFGetTypeID(num) == CFBooleanGetTypeID() { return nil }
            let doubleVal = num.doubleValue
            if !doubleVal.isFinite || floor(doubleVal) != doubleVal { return nil }
            text = String(num.int64Value)
        } else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard digitsRegex.firstMatch(in: text, range: range) != nil,
              let number = Int64(text),
              number >= 1, number <= Int64(Int.max) else {
            return nil
        }
        return Int(number)
    }

    /// 校验音频直链并强制将喜马拉雅官方域名的 HTTP 升级为 HTTPS
    public static func mediaUri(_ value: String) throws -> String {
        guard !value.isEmpty, value.count <= 16384 else {
            throw XmlyException(code: "invalid_media", message: "音频地址无效")
        }
        if value.unicodeScalars.contains(where: { $0.value <= 0x20 }) {
            throw XmlyException(code: "invalid_media", message: "音频地址无效")
        }
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil else {
            throw XmlyException(code: "invalid_media", message: "音频地址无效")
        }
        let isDefaultHttpPort = components.port == nil || components.port == 80
        let isXimalayaHost = host == "xmcdn.com" || host.hasSuffix(".xmcdn.com")
            || host == "ximalaya.com" || host.hasSuffix(".ximalaya.com")
        if scheme == "http" && isDefaultHttpPort && isXimalayaHost {
            return "https://" + value.dropFirst("http://".count)
        }
        return value
    }

    /// 从接口字典提取封面地址，并将 xmcdn 链接升级为 HTTPS
    public static func coverUrl(from raw: [String: Any]) -> String? {
        for key in coverKeys {
            guard let value = raw[key] as? String,
                  !value.isEmpty, value.count <= 16384,
                  !value.unicodeScalars.contains(where: { $0.value <= 0x20 }) else {
                continue
            }
            let normalized = value.hasPrefix("//") ? "https:\(value)" : value
            guard let components = URLComponents(string: normalized),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = components.host?.lowercased(), !host.isEmpty,
                  components.user == nil, components.password == nil else {
                continue
            }
            if scheme == "http" && (host == "xmcdn.com" || host.hasSuffix(".xmcdn.com")) {
                return "https://" + normalized.dropFirst("http://".count)
            }
            return normalized
        }
        return nil
    }

    /// 规范化 CDN 头像/封面地址
    public static func cdnUrl(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 16384,
              !trimmed.unicodeScalars.contains(where: { $0.value <= 0x20 }) else {
            return nil
        }
        let normalized = trimmed.hasPrefix("//") ? "https:\(trimmed)" : trimmed
        guard let components = URLComponents(string: normalized),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil else {
            return nil
        }
        if scheme == "http" && (host == "xmcdn.com" || host.hasSuffix(".xmcdn.com")) {
            return "https://" + normalized.dropFirst("http://".count)
        }
        return normalized
    }

    /// 从标题（如“第2347集”）猜测剧集序号，仅作为快速定位分页的提示
    public static func episodeHint(from title: String) -> Int? {
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        guard let match = episodeRegex.firstMatch(in: title, range: range),
              let numRange = Range(match.range(at: 1), in: title) else {
            return nil
        }
        return Int(title[numRange])
    }
}
