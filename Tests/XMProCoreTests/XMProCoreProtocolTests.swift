import Foundation
import Testing
@testable import XMProCore

@Suite("XMProCore 协议与模型对拍测试")
struct XMProCoreProtocolTests {

    @Test("AES 播放载荷加密解密往返与折行格式")
    func playPayloadRoundTrip() throws {
        let json = #"{"trackId":123456,"bitRate":64000,"duration":301}"#
        let envelope = try XmlyCrypto.encrypt(json, key: XmlyCrypto.playKey)
        #expect(envelope.hasSuffix("\n"))
        let decrypted = try XmlyCrypto.decrypt(envelope, key: XmlyCrypto.playKey)
        #expect(decrypted == json)
    }

    @Test("解密兼容无换行的单行 URL-Safe Base64")
    func decryptUnwrappedBase64() throws {
        let json = #"{"title":"第一集","ok":true}"#
        let envelope = try XmlyCrypto.encrypt(json, key: XmlyCrypto.durationKey)
        let flattened = envelope.replacingOccurrences(of: "\n", with: "")
        #expect(try XmlyCrypto.decrypt(flattened, key: XmlyCrypto.durationKey) == json)
    }

    @Test("非法密文抛出 invalid_encoding")
    func decryptRejectsMalformed() {
        for bad in ["", "not base64!!", "QUJD"] {
            do {
                _ = try XmlyCrypto.decrypt(bad, key: XmlyCrypto.playKey)
                Issue.record("预期 '\(bad)' 解密失败")
            } catch let err as XmlyException {
                #expect(err.code == "invalid_encoding")
            } catch {
                Issue.record("错误类型不符: \(error)")
            }
        }
    }

    @Test("听时活动签名严格对齐原仓库参考向量")
    func activitySignatureMatchesReference() {
        #expect(
            XmlyCrypto.activitySignature(["a": "b", "z": "Z"]) == "a6fec7af506479d08f411bf040d8c762"
        )
        #expect(
            XmlyCrypto.activitySignature(["uid": "123", "count": "2"]) == "4a8f64e65478ecc6c823c708bb70c9b0"
        )
    }

    @Test("TAC 票据二进制结构与自定义属性正确")
    func tacTicketLayoutAndAttributes() throws {
        let creds = try Credentials(rawToken: "123456&abcdef", rawDeviceId: "android-0123456789abcdef")
        let ticket = XmlyCrypto.freshTicket(credentials: creds, nowSeconds: 1_700_000_000)
        #expect(ticket.hasPrefix("TAC"))

        var b64 = String(ticket.dropFirst(3))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = b64.count % 4
        if rem != 0 { b64 += String(repeating: "=", count: 4 - rem) }
        let body = try #require(Data(base64Encoded: b64))

        let suffix = "com.ximalaya.ting.lite!1.3.24!3.4.10.3!b=lite&s=lite_track_play_url&&u=123456"
        #expect(body.count == 4 + 16 + 16 + 32 + suffix.utf8.count)
        let ts = (UInt32(body[0]) << 24) | (UInt32(body[1]) << 16) | (UInt32(body[2]) << 8) | UInt32(body[3])
        #expect(ts == 1_700_000_000)
        let tail = String(data: body.suffix(suffix.utf8.count), encoding: .utf8)
        #expect(tail == suffix)

        let customTicket = XmlyCrypto.freshTicket(credentials: creds, attributes: "custom")
        var cb64 = String(customTicket.dropFirst(3))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let crem = cb64.count % 4
        if crem != 0 { cb64 += String(repeating: "=", count: 4 - crem) }
        let cbody = try #require(Data(base64Encoded: cb64))
        #expect(String(data: cbody.suffix(6), encoding: .utf8) == "custom")
    }

    @Test("历史同步签名对齐已知向量且保护非 ASCII 字符")
    func historySignatureMatchesReference() {
        #expect(
            XmlyHistory.signature(["token": "abc", "uid": "1"]) == "2b9b3889caf58e979e28ee0265c960d3"
        )
        #expect(
            XmlyHistory.signature(["a": "1", "b": "2"]) == XmlyHistory.signature(["b": "2", "a": "1"])
        )
        #expect(XmlyHistory.signature(["title": "测试"]).count == 32)
    }

    @Test("短信登录 RSA 手机号加密 128 字节且随机填充")
    func rsaMobileEncryptionAndLoginSignature() throws {
        let enc1 = try XmlyLogin.encryptMobile("13800000000")
        let enc2 = try XmlyLogin.encryptMobile("13800000000")
        let bytes1 = try #require(Data(base64Encoded: enc1))
        #expect(bytes1.count == 128)
        #expect(bytes1.contains { $0 != 0 })
        #expect(enc1 != enc2)

        let sig1 = XmlyLogin.signature(["b": "2", "a": "1"])
        let sig2 = XmlyLogin.signature(["a": "1", "b": "2"])
        #expect(sig1 == sig2)
        #expect(sig1.count == 40)
        #expect(sig1.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test("Cookie / JSON 凭据解析与脱敏保护")
    func credentialsParsingAndRedaction() throws {
        let cookie = "1&_token=123456&abcdef; 1&_device=android&device-id-1&3.4.10; channel=and-f5"
        let c1 = try Credentials.parse(cookie)
        #expect(c1.token == "123456&abcdef")
        #expect(c1.deviceId == "device-id-1")
        #expect(c1.uid == "123456")
        #expect(!c1.description.contains("abcdef"))

        let json = #"{"xmly":{"config":{"token":"123456&abcdef","device_id":"dev-1"}}}"#
        let c2 = try Credentials.parse(json)
        #expect(c2.token == "123456&abcdef")
        #expect(c2.deviceId == "dev-1")

        let direct = try Credentials(rawToken: "123456&abcdef", rawDeviceId: "dev-1")
        let prefixed = try Credentials(rawToken: "1&_token=123456&abcdef", rawDeviceId: "dev-1")
        #expect(direct.identity == prefixed.identity)
        #expect(direct.identity.count == 64)

        let ambiguous = "1&_token=123&abc; 1&_token=456&def; 1&_device=android&dev&3.4.10"
        #expect(throws: XmlyException.self) {
            _ = try Credentials.parse(ambiguous)
        }
        #expect(throws: XmlyException.self) {
            _ = try Credentials(rawToken: "abc", rawDeviceId: "dev")
        }
    }

    @Test("标识符校验、封面 HTTPS 升级与剧集序号猜测")
    func identifiersAndCoverUpgrades() throws {
        #expect(try XmlyIdentifiers.xmlyIdentifier("123456") == "123456")
        #expect(try XmlyIdentifiers.xmlyIdentifier("xmly:123456") == "123456")
        #expect(throws: XmlyException.self) { _ = try XmlyIdentifiers.xmlyIdentifier("0") }
        #expect(throws: XmlyException.self) { _ = try XmlyIdentifiers.xmlyIdentifier("../etc") }

        #expect(XmlyIdentifiers.xmlyPositive("7") == 7)
        #expect(XmlyIdentifiers.xmlyPositive(7) == 7)
        #expect(XmlyIdentifiers.xmlyPositive("0") == nil)
        #expect(XmlyIdentifiers.xmlyPositive("7.5") == nil)

        #expect(
            XmlyIdentifiers.coverUrl(from: ["coverLarge": "http://image.xmcdn.com/a.jpg"])
                == "https://image.xmcdn.com/a.jpg"
        )
        #expect(XmlyIdentifiers.coverUrl(from: ["coverSmall": "javascript:alert(1)"]) == nil)
        #expect(XmlyIdentifiers.episodeHint(from: "第2347集 大结局") == 2347)
    }

    @Test("加密凭据持久化与最近进度存储往返")
    func appStorageSealedCredentialsAndPositions() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("xmpro-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let storage = AppStorage(baseDirectory: tmp)
        #expect(storage.loadCredentials() == nil)

        let creds = try Credentials(rawToken: "998877&secret_tok", rawDeviceId: "mac-dev-01")
        try storage.saveCredentials(creds)
        let loaded = storage.loadCredentials()
        #expect(loaded == creds)

        // 校验磁盘文件不包含明文 token
        let rawFile = try Data(contentsOf: tmp.appendingPathComponent("credentials.sealed"))
        #expect(!String(decoding: rawFile, as: UTF8.self).contains("secret_tok"))

        let track = try Track(rawId: "888", title: "第一集", album: "测试专辑", albumId: "555", duration: 600)
        let map = storage.rememberPosition(track: track, positionSeconds: 123.5)
        #expect(map["555"]?.first?.positionSeconds == 123.5)
    }
}
