import Foundation
import Security

/// 喜马拉雅短信登录手机号 RSA/ECB/PKCS#1 v1.5 加密器（1024 位固定公钥）
public enum RSAMobileEncryptor {
    private static let modulusHex =
        "9585a4773abeecb949701d49762f2dfab9599ba19dfe1e1a2fa200e32e0444f426da528912" +
        "d9ea8669515f6f1014c454e1343b97abf7c10fe49d520a6999c66b230e0730c3f8" +
        "02d136a892501ff2b13d699b5c7ecbbfef428ac36d3d83a5bd627f18746a7fdc77" +
        "4c12a38de2760a3b95c653c10d7eb7f84722976251f649556b"

    /// 构造标准 ASN.1 DER PKCS#1 RSAPublicKey 并使用系统 Security 框架执行随机填充加密
    public static func encryptMobile(_ mobile: String) throws -> String {
        let keyData = buildRSAPublicKeyDER(modulusHex: modulusHex)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 1024,
        ]
        var keyError: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &keyError) else {
            throw XmlyException(code: "crypto_error", message: "无法初始化登录加密公钥", definitive: true)
        }
        var encError: Unmanaged<CFError>?
        let plain = Data(mobile.utf8)
        guard let encrypted = SecKeyCreateEncryptedData(
            secKey,
            .rsaEncryptionPKCS1,
            plain as CFData,
            &encError
        ) as Data? else {
            throw XmlyException(code: "crypto_error", message: "手机号加密失败", definitive: true)
        }
        // 确保为完整 128 字节 1024-bit 密文块
        let padded: Data
        if encrypted.count < 128 {
            padded = Data(repeating: 0, count: 128 - encrypted.count) + encrypted
        } else {
            padded = encrypted
        }
        return padded.base64EncodedString()
    }

    /// 组装 PKCS#1 RSAPublicKey ASN.1 DER 序列：`SEQUENCE { INTEGER modulus, INTEGER 65537 }`
    private static func buildRSAPublicKeyDER(modulusHex: String) -> Data {
        let modulusBytes = XmlyCrypto.hexData(modulusHex)
        var modIntegerPayload = Data()
        if let first = modulusBytes.first, (first & 0x80) != 0 {
            modIntegerPayload.append(0x00)
        }
        modIntegerPayload.append(modulusBytes)

        var modTLV = Data([0x02])
        modTLV.append(derLength(modIntegerPayload.count))
        modTLV.append(modIntegerPayload)

        // 公钥指数 65537 = 0x010001
        let expTLV = Data([0x02, 0x03, 0x01, 0x00, 0x01])

        let seqContentLength = modTLV.count + expTLV.count
        var der = Data([0x30])
        der.append(derLength(seqContentLength))
        der.append(modTLV)
        der.append(expTLV)
        return der
    }

    private static func derLength(_ length: Int) -> Data {
        if length < 0x80 {
            return Data([UInt8(length)])
        } else if length <= 0xFF {
            return Data([0x81, UInt8(length)])
        } else {
            return Data([0x82, UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)])
        }
    }
}
