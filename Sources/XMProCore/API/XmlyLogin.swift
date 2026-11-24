import Foundation

/// 喜马拉雅短信验证码登录客户端
/// 手机号采用 RSA PKCS#1 v1.5 加密，挑战态仅存内存且所有 POST 请求永不自动重放
public final class XmlyLogin: @unchecked Sendable {
    public static let captchaId = "3723312ce42a04b5c0b40e605a882037"
    public static let passportOrigin = "https://passport.ximalaya.com"
    public static let requiredCaptchaFields = [
        "captcha_id",
        "lot_number",
        "pass_token",
        "gen_time",
        "captcha_output",
    ]
    private static let salt = "MOBILE-V1-PRODUCT-7D74899B338B4F348E2383970CC09991E8E8D8F2BC744EF0BEE94D76D718C089"
    private static let maxBytes = 512 * 1024

    private static let mobileRegex = try! NSRegularExpression(pattern: "^\\+?[0-9]{6,18}$")
    private static let captchaValueRegex = try! NSRegularExpression(pattern: "^[\\x21-\\x7e]{1,8192}$")
    private static let challengeIdRegex = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]{1,128}$")
    private static let codeRegex = try! NSRegularExpression(pattern: "^[0-9]{4,8}$")
    private static let retRegex = try! NSRegularExpression(pattern: "^-?[0-9]{1,9}$")
    private static let uidRegex = try! NSRegularExpression(pattern: "^[1-9][0-9]{0,19}$")
    private static let tokenRegex = try! NSRegularExpression(pattern: "^[A-Za-z0-9._~+/=\\-]{1,8192}$")

    private final class PendingChallenge {
        let id: String
        let encryptedMobile: String
        let deviceId: String
        let expiresAtMillis: Int64
        var attempts: Int = 0

        init(id: String, encryptedMobile: String, deviceId: String, expiresAtMillis: Int64) {
            self.id = id
            self.encryptedMobile = encryptedMobile
            self.deviceId = deviceId
            self.expiresAtMillis = expiresAtMillis
        }
    }

    private let session: URLSession
    private let delegate: NoRedirectSessionDelegate
    private let clock: ServerClock
    private let defaultDeviceId: String

    private let lock = NSLock()
    private var pending: PendingChallenge?
    private var generation: Int = 0
    private var lastSms: [String: Int64] = [:]
    private var usedLots: [String: Int64] = [:]

    public init(deviceOverride: String? = nil, clock: ServerClock = .shared) {
        self.clock = clock
        self.defaultDeviceId = (deviceOverride?.isEmpty == false) ? deviceOverride! : UUID().uuidString.lowercased()
        self.delegate = NoRedirectSessionDelegate()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 25
        cfg.httpShouldSetCookies = false
        cfg.httpCookieAcceptPolicy = .never
        self.session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
    }

    /// 关闭登录弹窗时清理内存中的临时短信挑战状态
    public func clear() {
        lock.lock()
        generation += 1
        pending = nil
        lock.unlock()
    }

    /// 登录接口签名：按键名升序拼接 `k=v&`，全转大写后再拼接固定盐做 SHA-1
    public static func signature(_ values: [String: String]) -> String {
        var canonical = ""
        for key in values.keys.sorted() {
            canonical += "\(key)=\(values[key] ?? "")&"
        }
        let upper = canonical.uppercased() + salt
        return XmlyCrypto.sha1Hex(Data(upper.utf8))
    }

    public static func encryptMobile(_ mobile: String) throws -> String {
        try RSAMobileEncryptor.encryptMobile(mobile)
    }

    /// 携带用户手动完成的 GeeTest v4 结果发送登录短信验证码，返回 challengeId
    public func sendSms(
        mobile: String,
        geetest: [String: String],
        device: String = ""
    ) async throws -> String {
        let trimmedMobile = mobile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard matches(Self.mobileRegex, trimmedMobile) else {
            throw XmlyException(code: "invalid_mobile", message: "手机号格式无效", definitive: true)
        }
        for key in Self.requiredCaptchaFields {
            guard let val = geetest[key], matches(Self.captchaValueRegex, val) else {
                throw XmlyException(code: "invalid_captcha", message: "安全验证字段无效", definitive: true)
            }
        }
        guard geetest["captcha_id"]?.caseInsensitiveCompare(Self.captchaId) == .orderedSame else {
            throw XmlyException(code: "invalid_captcha", message: "安全验证字段无效", definitive: true)
        }
        if device.count > 128 || device.unicodeScalars.contains(where: { $0.value <= 32 || $0.value >= 127 || ";&,\\\"\\".unicodeScalars.contains($0) }) {
            throw XmlyException(code: "invalid_device", message: "登录设备标识无效", definitive: true)
        }

        let lotHash = XmlyCrypto.sha256Hex(geetest["lot_number"] ?? "")
        let phoneNormalized = trimmedMobile.hasPrefix("+") ? String(trimmedMobile.dropFirst()) : trimmedMobile
        let phoneHash = XmlyCrypto.sha256Hex(phoneNormalized)
        let now = clock.nowMillis()

        let (currentGeneration, targetDevice) = try withLock { () -> (Int, String) in
            usedLots = usedLots.filter { now - $0.value < 600_000 }
            lastSms = lastSms.filter { now - $0.value < 180_000 }
            if let seen = usedLots[lotHash], now - seen < 600_000 {
                throw XmlyException(code: "captcha_reused", message: "本次安全验证已使用，请重新验证", definitive: true)
            }
            if let last = lastSms[phoneHash], now - last < 180_000 {
                let remain = ((180_000 - (now - last)) + 999) / 1000
                throw XmlyException(code: "sms_cooldown", message: "请在 \(remain) 秒后重新发送短信", definitive: true)
            }
            usedLots[lotHash] = now
            lastSms[phoneHash] = now
            pending = nil
            return (generation, device.isEmpty ? defaultDeviceId : device)
        }

        let encrypted = try Self.encryptMobile(trimmedMobile)
        let nonceValue = try await fetchNonce(device: targetDevice)

        guard withLock({ generation == currentGeneration }) else {
            throw XmlyException(code: "challenge_invalid", message: "短信验证已取消", definitive: true)
        }

        var otpMap: [String: String] = [:]
        for key in Self.requiredCaptchaFields {
            otpMap[key] = geetest[key] ?? ""
        }
        let otpData = try JSONSerialization.data(withJSONObject: otpMap, options: [])
        let otpString = String(data: otpData, encoding: .utf8) ?? "{}"

        let values: [String: String] = [
            "mobile": encrypted,
            "sendType": "1",
            "biz": "1",
            "nonce": nonceValue,
            "fdsOtp": otpString,
        ]
        _ = try await post(path: "mobile/sms/v3/send", device: targetDevice, values: values, operation: "sms_send")

        let challengeId = XmlyCrypto.base64UrlNoPadding(Data(XmlyCrypto.randomBytes(count: 32)))
        try withLock {
            guard generation == currentGeneration else {
                throw XmlyException(code: "challenge_invalid", message: "短信验证已取消", definitive: true)
            }
            pending = PendingChallenge(
                id: challengeId,
                encryptedMobile: encrypted,
                deviceId: targetDevice,
                expiresAtMillis: now + 600_000
            )
        }
        return challengeId
    }

    /// 校验短信验证码并换取账号 Credentials 与基础资料
    public func verifySms(challengeId: String, code: String) async throws -> LoginResult {
        guard matches(Self.challengeIdRegex, challengeId) else {
            throw XmlyException(code: "challenge_invalid", message: "需要有效的短信验证请求", definitive: true)
        }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard matches(Self.codeRegex, trimmedCode) else {
            throw XmlyException(code: "invalid_code", message: "短信验证码必须为 4 至 8 位数字", definitive: true)
        }

        let active = try withLock { () -> PendingChallenge in
            guard let current = pending, current.id == challengeId else {
                throw XmlyException(code: "challenge_invalid", message: "短信验证不存在或已完成", definitive: true)
            }
            if clock.nowMillis() >= current.expiresAtMillis {
                pending = nil
                throw XmlyException(code: "challenge_expired", message: "短信验证已过期，请重新发送", definitive: true)
            }
            current.attempts += 1
            return current
        }

        defer {
            withLock {
                if active.attempts >= 5 && pending === active {
                    pending = nil
                }
            }
        }

        let verifyNonce = try await fetchNonce(device: active.deviceId)
        try ensureStillActive(active)

        let verifyResult = try await post(
            path: "mobile/sms/v2/verify",
            device: active.deviceId,
            values: [
                "mobile": active.encryptedMobile,
                "code": trimmedCode,
                "nonce": verifyNonce,
            ],
            operation: "sms_verify"
        )
        let rawKey = (verifyResult["bizKey"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (verifyResult["smsKey"] as? String)
        guard let smsKey = rawKey, !smsKey.isEmpty, smsKey.count <= 8192 else {
            throw XmlyException(code: "invalid_response", message: "登录响应缺少有效短信密钥")
        }

        try ensureStillActive(active)
        let loginNonce = try await fetchNonce(device: active.deviceId)
        try ensureStillActive(active)

        let loginResp = try await post(
            path: "mobile/login/quick/v2",
            device: active.deviceId,
            values: [
                "mobile": active.encryptedMobile,
                "smsKey": smsKey,
                "nonce": loginNonce,
            ],
            operation: "quick_login"
        )
        try ensureStillActive(active)

        let nested = loginResp["data"] as? [String: Any]
        let uid = nonBlankString(loginResp["uid"]) ?? nonBlankString(nested?["uid"]) ?? ""
        let token = (loginResp["token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (nested?["token"] as? String) ?? ""

        guard matches(Self.uidRegex, uid), matches(Self.tokenRegex, token) else {
            throw XmlyException(code: "invalid_response", message: "登录响应缺少有效账号凭据")
        }

        withLock {
            pending = nil
        }

        let credentials = try Credentials(rawToken: "\(uid)&\(token)", rawDeviceId: active.deviceId)
        let nickname = JSONHelpers.findFirstString(in: loginResp, keys: ["nickname", "userName", "nickName"]) ?? ""
        let avatar = JSONHelpers.findFirstString(in: loginResp, keys: ["avatar", "avatarUrl", "logoPic", "smallLogo"])
        let mobileOut = JSONHelpers.findFirstString(in: loginResp, keys: ["mobile", "phone", "mobilePhone"]) ?? ""
        return LoginResult(
            credentials: credentials,
            nickname: nickname,
            avatarUrl: XmlyIdentifiers.cdnUrl(avatar),
            mobile: mobileOut
        )
    }

    // MARK: - 内部请求实现

    private func ensureStillActive(_ active: PendingChallenge) throws {
        try withLock {
            guard pending === active else {
                throw XmlyException(code: "challenge_invalid", message: "短信验证已取消或被替换", definitive: true)
            }
            if clock.nowMillis() >= active.expiresAtMillis {
                pending = nil
                throw XmlyException(code: "challenge_expired", message: "短信验证已过期，请重新发送", definitive: true)
            }
        }
    }

    private func fetchNonce(device: String) async throws -> String {
        let result = try await sendRequest(
            method: "GET",
            path: "mobile/nonce/\(clock.nowMillis())",
            device: device,
            bodyData: nil
        )
        if result["ret"] != nil {
            try checkRet(result, operation: "nonce")
        }
        guard let nonce = result["nonce"] as? String, !nonce.isEmpty, nonce.count <= 1024 else {
            throw XmlyException(code: "invalid_response", message: "登录响应缺少有效 nonce")
        }
        return nonce
    }

    private func post(
        path: String,
        device: String,
        values: [String: String],
        operation: String
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [:]
        for (k, v) in values { payload[k] = v }
        payload["signature"] = Self.signature(values)
        let bodyData = try JSONSerialization.data(withJSONObject: payload, options: [])
        let result = try await sendRequest(method: "POST", path: path, device: device, bodyData: bodyData)
        try checkRet(result, operation: operation)
        return result
    }

    private func checkRet(_ result: [String: Any], operation: String) throws {
        let ret = JSONHelpers.string(result["ret"])
        guard matches(Self.retRegex, ret) else {
            throw XmlyException(code: "invalid_response", message: "登录响应状态无效")
        }
        if ret != "0" {
            let msg = JSONHelpers.string(result["msg"])
            let detail = msg.isEmpty ? "登录请求未成功（错误码 \(ret)），请重新验证" : "\(msg)（错误码 \(ret)）"
            throw XmlyException(code: "\(operation)_rejected", message: detail, definitive: true)
        }
    }

    private func sendRequest(
        method: String,
        path: String,
        device: String,
        bodyData: Data?
    ) async throws -> [String: Any] {
        guard let url = URL(string: "\(Self.passportOrigin)/\(path)") else {
            throw XmlyException(code: "invalid_url", message: "登录服务地址无效", definitive: true)
        }
        let cookie = "1&_device=android&\(device)&9.5.1;channel=and-d10;" +
            "impl=com.ximalaya.ting.android;qimei36=;osversion=31;" +
            "device_model=M2102J2SC;XIM=;net-mode=WIFI;manufacturer=Xiaomi;"

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("ting_9.5.1(M2102J2SC,Android31)", forHTTPHeaderField: "User-Agent")
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        req.setValue("$version=1", forHTTPHeaderField: "Cookie2")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        if let bodyData {
            req.httpBody = bodyData
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let attempts = (method == "GET") ? 4 : 1
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                let (data, response) = try await session.data(for: req)
                if data.count > Self.maxBytes {
                    throw XmlyException(code: "response_too_large", message: "登录响应超出大小限制")
                }
                guard let httpResp = response as? HTTPURLResponse else {
                    throw XmlyException(code: "network_error", message: "登录连接失败或超时，请勿自动重发短信")
                }
                if httpResp.statusCode != 200 {
                    let definitive = (400...499).contains(httpResp.statusCode) && httpResp.statusCode != 429
                    throw XmlyException(
                        code: "http_error",
                        message: "登录服务请求失败（HTTP \(httpResp.statusCode)）",
                        definitive: definitive
                    )
                }
                guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw XmlyException(code: "invalid_response", message: "登录响应格式无效")
                }
                return parsed
            } catch let error as XmlyException {
                if error.code != "http_error" || error.definitive || attempt == attempts - 1 {
                    throw error
                }
                lastError = error
            } catch {
                if method != "GET" || attempt == attempts - 1 {
                    throw XmlyException(code: "network_error", message: "登录连接失败或超时，请勿自动重发短信")
                }
                lastError = error
            }
            let delayNs = UInt64(500_000_000) << attempt
            try await Task.sleep(nanoseconds: delayNs)
        }
        throw XmlyException(
            code: "network_error",
            message: lastError?.localizedDescription ?? "登录连接失败或超时，请勿自动重发短信"
        )
    }

    private func nonBlankString(_ value: Any?) -> String? {
        let s = JSONHelpers.string(value)
        return (s.isEmpty || s == "0" || s == "false") ? nil : s
    }

    private func matches(_ regex: NSRegularExpression, _ value: String) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
