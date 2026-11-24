import CommonCrypto
import CryptoKit
import Foundation
import Security

/// 喜马拉雅极速版协议加解密与签名实现
/// 所有密钥常量与字节排布均严格对齐 angusdevgo/XMPro 原实现
public enum XmlyCrypto {
    public static let playKey: Data = hexData("bf56792c145e706d1dd26c04feba6a8c")
    public static let durationKey: Data = Data("jkq1hsksjxg4mf2y".utf8)
    private static let ticketMaterial: Data = hexData("b0b1a8ac34e66efa95c7f4157cf8b6ba33dfc2075e41fb964f2e12dcaa")
    private static let activityMaterial = "q35435432sadks2i3546p2ndkcaqiwurhqfebt4kn"

    private static let base64AlphabetRegex = try! NSRegularExpression(pattern: "^[A-Za-z0-9+/_\\-]*={0,2}$")

    /// 将 UTF-8 字符串加密为带 76 字符折行与尾换行的 URL-Safe Base64 密文包
    public static func encrypt(_ plaintext: String, key: Data) throws -> String {
        let raw = Data(plaintext.utf8)
        guard raw.count <= 2 * 1024 * 1024 else {
            throw XmlyException(code: "invalid_encoding", message: "协议数据过大")
        }
        let cipherData = try aesECBCrypt(data: raw, key: key, operation: CCOperation(kCCEncrypt))
        let encoded = base64UrlNoPadding(cipherData)
        return chunked(encoded, size: 76).joined(separator: "\n") + "\n"
    }

    /// 解密喜马拉雅接口返回的折行或单行 URL-Safe/标准 Base64 AES-ECB 密文
    public static func decrypt(_ value: String, key: Data) throws -> String {
        do {
            guard value.count <= 4 * 1024 * 1024 else {
                throw XmlyException(code: "invalid_encoding", message: "too long")
            }
            let text = value.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard base64AlphabetRegex.firstMatch(in: text, range: range) != nil else {
                throw XmlyException(code: "invalid_encoding", message: "invalid alphabet")
            }
            var normalized = text
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let rem = normalized.count % 4
            if rem != 0 {
                normalized += String(repeating: "=", count: 4 - rem)
            }
            guard let bytes = Data(base64Encoded: normalized),
                  !bytes.isEmpty,
                  bytes.count % kCCBlockSizeAES128 == 0 else {
                throw XmlyException(code: "invalid_encoding", message: "invalid length")
            }
            let plainData = try aesECBCrypt(data: bytes, key: key, operation: CCOperation(kCCDecrypt))
            guard let output = String(data: plainData, encoding: .utf8) else {
                throw XmlyException(code: "invalid_encoding", message: "invalid utf8")
            }
            return output
        } catch {
            throw XmlyException(
                code: "invalid_encoding",
                message: "喜马拉雅播放协议解码失败，可能需要更新客户端协议"
            )
        }
    }

    /// 活动/听时接口签名：按键名升序拼接 `k=v&` + 固定盐，仅对 ASCII 大写转小写后做 MD5
    public static func activitySignature(_ params: [String: String]) -> String {
        var canonical = ""
        for key in params.keys.sorted() {
            canonical += "\(key)=\(params[key] ?? "")&"
        }
        canonical += activityMaterial
        return md5Hex(asciiLowercasedUTF8(canonical))
    }

    /// 生成认证声音接口与福利接口所需的 TAC 票据
    public static func freshTicket(
        credentials: Credentials,
        attributes: String? = nil,
        nowSeconds: Int64? = nil
    ) -> String {
        let identityDigest = md5Data(Data("\(credentials.uid)|\(credentials.deviceId)".utf8))
        var uuid = randomBytes(count: 16)
        uuid[6] = (uuid[6] & 0x0F) | 0x40
        uuid[8] = (uuid[8] & 0x3F) | 0x80

        let seconds = UInt32(truncatingIfNeeded: nowSeconds ?? (ServerClock.shared.nowMillis() / 1000))
        var payload = Data(count: 36)
        payload[0] = UInt8((seconds >> 24) & 0xFF)
        payload[1] = UInt8((seconds >> 16) & 0xFF)
        payload[2] = UInt8((seconds >> 8) & 0xFF)
        payload[3] = UInt8(seconds & 0xFF)
        payload.replaceSubrange(4..<20, with: identityDigest)
        for i in 0..<16 {
            payload[20 + i] = uuid[i] ^ identityDigest[i]
        }

        let attr = attributes ?? "b=lite&s=lite_track_play_url&&u=\(credentials.uid)"
        let suffix = Data("com.ximalaya.ting.lite!1.3.24!3.4.10.3!\(attr)".utf8)

        var hasher = SHA256()
        hasher.update(data: payload)
        hasher.update(data: Data("TAC".utf8))
        hasher.update(data: ticketMaterial)
        hasher.update(data: suffix)
        let digest = Data(hasher.finalize())

        var body = Data(capacity: payload.count + digest.count + suffix.count)
        body.append(payload)
        body.append(digest)
        body.append(suffix)
        return "TAC" + base64UrlNoPadding(body)
    }

    // MARK: - 通用加密辅助函数

    /// 仅把 UTF-8 字节流中的 ASCII 大写字母（65..90）转为小写，避免影响中文等多字节字符
    public static func asciiLowercasedUTF8(_ value: String) -> Data {
        var bytes = [UInt8](value.utf8)
        for i in bytes.indices {
            if bytes[i] >= 65 && bytes[i] <= 90 {
                bytes[i] &+= 32
            }
        }
        return Data(bytes)
    }

    public static func md5Data(_ data: Data) -> Data {
        Data(Insecure.MD5.hash(data: data))
    }

    public static func md5Hex(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func md5Hex(_ string: String) -> String {
        md5Hex(Data(string.utf8))
    }

    public static func sha1Hex(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func base64UrlNoPadding(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func hexData(_ hex: String) -> Data {
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            let byte = UInt8(hex[index..<next], radix: 16) ?? 0
            data.append(byte)
            index = next
        }
        return data
    }

    public static func randomBytes(count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        if status != errSecSuccess {
            for i in 0..<count {
                bytes[i] = UInt8.random(in: 0...255)
            }
        }
        return bytes
    }

    private static func aesECBCrypt(data: Data, key: Data, operation: CCOperation) throws -> Data {
        let outLength = data.count + kCCBlockSizeAES128
        var outBytes = [UInt8](repeating: 0, count: outLength)
        var numBytesMoved: size_t = 0

        let status = key.withUnsafeBytes { keyPtr in
            data.withUnsafeBytes { dataPtr in
                CCCrypt(
                    operation,
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                    keyPtr.baseAddress,
                    key.count,
                    nil,
                    dataPtr.baseAddress,
                    data.count,
                    &outBytes,
                    outLength,
                    &numBytesMoved
                )
            }
        }
        guard status == kCCSuccess else {
            throw XmlyException(code: "invalid_encoding", message: "AES 加解密失败(\(status))")
        }
        return Data(bytes: outBytes, count: numBytesMoved)
    }

    private static func chunked(_ text: String, size: Int) -> [String] {
        guard !text.isEmpty else { return [""] }
        var result: [String] = []
        var idx = text.startIndex
        while idx < text.endIndex {
            let end = text.index(idx, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            result.append(String(text[idx..<end]))
            idx = end
        }
        return result
    }
}
