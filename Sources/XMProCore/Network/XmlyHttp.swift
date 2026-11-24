import Foundation

/// 禁止 URLSession 自动跳转的轻量代理，供 API 请求与手动追踪重定向使用
final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// 喜马拉雅移动端 HTTP 传输边界
/// 负责响应体大小限制、429 源级冷却、只读重试与写操作防重放、服务端时间校正及重定向追踪
public final class XmlyHttp: @unchecked Sendable {
    public static let searchOrigin = "https://www.ximalaya.com"
    public static let maxResponseBytes = 2 * 1024 * 1024
    private static let maxAttempts = 5

    public struct Outcome: Sendable {
        public let status: Int
        public let body: String
        public let url: String
        public let retryAfter: String?
    }

    private let session: URLSession
    private let delegate: NoRedirectSessionDelegate
    private let searchOrigin: String
    private let clock: ServerClock
    private let cooldownLock = NSLock()
    private var cooldowns: [String: Date] = [:]

    public init(
        searchOrigin: String = XmlyHttp.searchOrigin,
        clock: ServerClock = .shared,
        configuration: URLSessionConfiguration? = nil
    ) {
        self.searchOrigin = searchOrigin
        self.clock = clock
        self.delegate = NoRedirectSessionDelegate()
        let cfg = configuration ?? {
            let c = URLSessionConfiguration.ephemeral
            c.timeoutIntervalForRequest = 25
            c.timeoutIntervalForResource = 35
            c.httpShouldSetCookies = false
            c.httpCookieAcceptPolicy = .never
            c.requestCachePolicy = .reloadIgnoringLocalCacheData
            return c
        }()
        self.session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
    }

    public func get(
        origin: String,
        path: String,
        query: [String: String] = [:],
        credentials: Credentials? = nil,
        signed: Bool = false,
        readOnly: Bool = true,
        headers: [String: String] = [:],
        responseLimit: Int = XmlyHttp.maxResponseBytes
    ) async throws -> [String: Any] {
        try await execute(
            method: "GET",
            origin: origin,
            path: path,
            query: query,
            bodyData: nil,
            contentType: nil,
            credentials: credentials,
            signed: signed,
            readOnly: readOnly,
            responseLimit: responseLimit,
            headers: headers
        )
    }

    public func postJson(
        origin: String,
        path: String,
        query: [String: String] = [:],
        json: [String: Any] = [:],
        credentials: Credentials? = nil,
        signed: Bool = false,
        readOnly: Bool = true,
        responseLimit: Int = XmlyHttp.maxResponseBytes,
        headers: [String: String] = [:]
    ) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: json, options: [])
        return try await execute(
            method: "POST",
            origin: origin,
            path: path,
            query: query,
            bodyData: data,
            contentType: "application/json",
            credentials: credentials,
            signed: signed,
            readOnly: readOnly,
            responseLimit: responseLimit,
            headers: headers
        )
    }

    public func postForm(
        origin: String,
        path: String,
        query: [String: String] = [:],
        form: [String: String],
        credentials: Credentials? = nil,
        signed: Bool = false,
        readOnly: Bool = true,
        responseLimit: Int = XmlyHttp.maxResponseBytes,
        headers: [String: String] = [:]
    ) async throws -> [String: Any] {
        let encoded = form.map { key, value in
            "\(Self.formEncode(key))=\(Self.formEncode(value))"
        }.joined(separator: "&")
        return try await execute(
            method: "POST",
            origin: origin,
            path: path,
            query: query,
            bodyData: Data(encoded.utf8),
            contentType: "application/x-www-form-urlencoded",
            credentials: credentials,
            signed: signed,
            readOnly: readOnly,
            responseLimit: responseLimit,
            headers: headers
        )
    }

    /// 手动追踪音频跳转链（最多 4 跳），并将明文 HTTP 跳转升级为 HTTPS
    public func followRedirect(url: String) async -> String {
        var current = url
        for _ in 0..<4 {
            guard let targetURL = URL(string: current) else { return current }
            var req = URLRequest(url: targetURL)
            req.httpMethod = "GET"
            req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            req.setValue("*/*", forHTTPHeaderField: "Accept")
            do {
                let (_, response) = try await session.data(for: req)
                guard let httpResp = response as? HTTPURLResponse,
                      (300...399).contains(httpResp.statusCode),
                      let location = httpResp.value(forHTTPHeaderField: "Location"),
                      !location.isEmpty else {
                    return current
                }
                if location.hasPrefix("http://") {
                    current = "https://" + location.dropFirst("http://".count)
                } else {
                    current = location
                }
            } catch {
                return current
            }
        }
        return current
    }

    // MARK: - 内部请求管线

    private struct RetryableError: Error {}

    private func execute(
        method: String,
        origin: String,
        path: String,
        query: [String: String],
        bodyData: Data?,
        contentType: String?,
        credentials: Credentials?,
        signed: Bool,
        readOnly: Bool,
        responseLimit: Int,
        headers: [String: String]
    ) async throws -> [String: Any] {
        if signed && credentials == nil {
            throw XmlyException(code: "login_required", message: "签名请求需要登录", definitive: true)
        }

        for attempt in 0..<Self.maxAttempts {
            try await awaitCooldown(origin: origin)
            do {
                let outcome = try await send(
                    method: method,
                    origin: origin,
                    path: path,
                    query: query,
                    bodyData: bodyData,
                    contentType: contentType,
                    credentials: credentials,
                    signed: signed,
                    responseLimit: responseLimit,
                    headers: headers
                )
                return try interpret(
                    outcome: outcome,
                    origin: origin,
                    authenticated: credentials != nil,
                    retryAfterHeader: Self.parseRetryAfter(outcome.retryAfter),
                    readOnly: readOnly
                )
            } catch is RetryableError {
                if !readOnly || attempt == Self.maxAttempts - 1 {
                    throw XmlyException(
                        code: readOnly ? "network" : "uncertain",
                        message: readOnly ? "喜马拉雅服务暂时不可用" : "请求结果未知，请核对后重试"
                    )
                }
            } catch let xmly as XmlyException {
                throw xmly
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if !readOnly || attempt == Self.maxAttempts - 1 {
                    throw XmlyException(
                        code: readOnly ? "network" : "uncertain",
                        message: readOnly ? "请求失败或超时" : "请求结果未知，请核对后重试"
                    )
                }
            }

            let backoff = TimeInterval(1 << attempt)
            let wait = max(backoff, remainingCooldown(origin: origin))
            if wait > 0 {
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
        throw XmlyException(code: "network", message: "请求失败")
    }

    private func send(
        method: String,
        origin: String,
        path: String,
        query: [String: String],
        bodyData: Data?,
        contentType: String?,
        credentials: Credentials?,
        signed: Bool,
        responseLimit: Int,
        headers: [String: String]
    ) async throws -> Outcome {
        guard var components = URLComponents(string: origin + path) else {
            throw XmlyException(code: "invalid_url", message: "请求地址无效", definitive: true)
        }
        if !query.isEmpty {
            var items = components.queryItems ?? []
            for key in query.keys.sorted() {
                items.append(URLQueryItem(name: key, value: query[key]))
            }
            components.queryItems = items
        }
        guard let url = components.url else {
            throw XmlyException(code: "invalid_url", message: "请求地址无效", definitive: true)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("close", forHTTPHeaderField: "Connection")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let credentials {
            request.setValue(credentials.cookie, forHTTPHeaderField: "Cookie")
        }
        if signed {
            guard let credentials else {
                throw XmlyException(code: "login_required", message: "签名请求需要登录", definitive: true)
            }
            request.setValue(XmlyCrypto.freshTicket(credentials: credentials), forHTTPHeaderField: "x-tk")
        }
        if let bodyData {
            request.httpBody = bodyData
            if let contentType {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse else {
            throw XmlyException(code: "network", message: "响应格式无效")
        }
        if data.count > responseLimit {
            throw XmlyException(
                code: "response_too_large",
                message: "响应超过 \(responseLimit / (1024 * 1024)) MiB 上限"
            )
        }
        clock.observeDateHeader(httpResp.value(forHTTPHeaderField: "Date"))
        let text = String(data: data, encoding: .utf8) ?? ""
        return Outcome(
            status: httpResp.statusCode,
            body: text,
            url: url.absoluteString,
            retryAfter: httpResp.value(forHTTPHeaderField: "Retry-After")
        )
    }

    private func interpret(
        outcome: Outcome,
        origin: String,
        authenticated: Bool,
        retryAfterHeader: TimeInterval?,
        readOnly: Bool
    ) throws -> [String: Any] {
        let status = outcome.status
        if status == 429 {
            let wait = retryAfterHeader ?? 30
            setCooldown(origin: origin, seconds: wait)
            throw XmlyException(
                code: "rate_limited",
                message: "请求过于频繁，请稍后重试",
                retryAfterSeconds: wait,
                definitive: true
            )
        }
        if status == 401 || (status == 403 && authenticated) {
            throw XmlyException(code: "login_expired", message: "登录信息已失效，请重新登录", definitive: true)
        }
        if (500...599).contains(status) {
            throw RetryableError()
        }
        if status != 200 {
            let clientError = (400...499).contains(status)
            throw XmlyException(
                code: clientError ? "rejected" : "protocol",
                message: "接口返回 HTTP \(status)",
                definitive: clientError
            )
        }
        guard !outcome.body.isEmpty else {
            throw XmlyException(code: "invalid_json", message: "接口响应为空")
        }
        guard let data = outcome.body.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw XmlyException(code: "invalid_json", message: "接口返回无效 JSON")
        }
        clock.observePayload(payload)

        let expected = (origin == searchOrigin) ? "200" : "0"
        let code: String
        if let rawRet = payload["ret"] {
            if let num = rawRet as? NSNumber {
                code = num.stringValue
            } else {
                code = "\(rawRet)"
            }
        } else {
            code = "0"
        }

        if code != expected {
            if code == "429" {
                setCooldown(origin: origin, seconds: 30)
                throw XmlyException(
                    code: "rate_limited",
                    message: "请求过于频繁，请稍后重试",
                    retryAfterSeconds: 30,
                    definitive: true
                )
            }
            if code == "401" {
                throw XmlyException(code: "login_expired", message: "登录信息已失效，请重新登录", definitive: true)
            }
            if ["5", "403", "726"].contains(code) {
                throw XmlyException(
                    code: "permission_denied",
                    message: "未获得本次请求的完整权限，请检查账号、听时和版权限制",
                    definitive: true
                )
            }
            if code == "4" || code == "-4" {
                throw XmlyException(
                    code: "rejected",
                    message: "喜马拉雅拒绝了请求（ret=\(code)）：听时额度或设备状态异常，请到官方 App 核对后再试",
                    definitive: true
                )
            }
            if code == "-400" {
                throw XmlyException(
                    code: "bad_timestamp",
                    message: "请求校验失败（设备时间与服务端偏差过大），请校准时间后重试",
                    definitive: true
                )
            }
            if code == "-1" {
                if readOnly { throw RetryableError() }
                throw XmlyException(code: "uncertain", message: "请求结果未知，请核对后重试")
            }
            throw XmlyException(
                code: "rejected",
                message: "喜马拉雅拒绝了请求（ret=\(code)）",
                definitive: true
            )
        }
        return payload
    }

    private func setCooldown(origin: String, seconds: TimeInterval) {
        cooldownLock.lock()
        cooldowns[origin] = Date().addingTimeInterval(seconds)
        cooldownLock.unlock()
    }

    private func remainingCooldown(origin: String) -> TimeInterval {
        cooldownLock.lock()
        let until = cooldowns[origin]
        cooldownLock.unlock()
        guard let until else { return 0 }
        return max(0, until.timeIntervalSinceNow)
    }

    private func awaitCooldown(origin: String) async throws {
        let remaining = remainingCooldown(origin: origin)
        if remaining > 0 {
            try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
    }

    public static func parseRetryAfter(_ value: String?) -> TimeInterval? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(trimmed), seconds >= 0 {
            return seconds
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = df.date(from: trimmed) {
            let delta = date.timeIntervalSinceNow
            return delta >= 0 ? delta : nil
        }
        return nil
    }

    /// 表单编码（遵循 application/x-www-form-urlencoded 规范）
    public static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        let escaped = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        return escaped.replacingOccurrences(of: " ", with: "+")
    }
}
