import Foundation

/// 听时福利任务：查询福利档位、单次安全领取、自动补充额度
/// 注意：所有领取 POST 均单次发送不重放，避免重复记账或触发风控
public final class XmlyRewards: @unchecked Sendable {
    private static let path = "/lite-earn/ting/welfare"
    private static let salt = "0ab3443b71834b33be675af744d76ef0aaa74cd2b60c4b67"
    private static let maxClaimsPerPass = 64

    private let client: XmlyClient
    private let clock: ServerClock

    public private(set) var lastMessage: String = ""

    public init(client: XmlyClient, clock: ServerClock = .shared) {
        self.client = client
        self.clock = clock
    }

    /// 获取听时福利档位列表（含每档秒数与最近到账时间）
    public func tiers() async throws -> [RewardTier] {
        _ = try validatedUid()
        let response = try await client.request(
            method: "GET",
            origin: XmlyClient.welfareOrigin,
            path: "\(Self.path)/queryVipDurationTask/ts-\(clock.nowMillis())"
        )
        let data = try validateResult(response)
        guard let list = data["tierList"] as? [[String: Any]] else { return [] }
        var result: [RewardTier] = []
        for (idx, row) in list.enumerated() {
            guard let seconds = JSONHelpers.int(row["tierDuration"]), seconds > 0 else { continue }
            let desc = JSONHelpers.string(row["tierDurationDesc"])
            let label = desc.isEmpty ? "\(seconds / 60) 分钟" : desc
            result.append(RewardTier(
                index: JSONHelpers.int(row["index"]) ?? idx,
                seconds: seconds,
                label: label,
                status: JSONHelpers.signedInt(row["status"]) ?? -1,
                receiveTimeMillis: JSONHelpers.int64(row["receiveTime"]) ?? 0
            ))
        }
        return result.sorted { $0.seconds < $1.seconds }
    }

    /// 单次领取听时福利（写操作，严格禁止自动重放）
    @discardableResult
    public func claim() async throws -> [String: Any] {
        guard let account = client.credentials else {
            throw XmlyException(code: "login_expired", message: "领取听时需要有效的登录态", definitive: true)
        }
        let owner = try validatedUid()
        let requestId = UUID().uuidString.lowercased()
        let timestamp = clock.nowMillis()
        let signSource = "\(requestId)&\(owner)&\(timestamp)&\(Self.salt)"

        let payload: [String: Any] = [
            "requestId": requestId,
            "uid": Int64(owner) ?? 0,
            "ts": timestamp,
            "signature": XmlyCrypto.md5Hex(signSource),
            "ticket": XmlyCrypto.freshTicket(
                credentials: account,
                attributes: "b=lite&s=lite_time_reward&u=\(owner)"
            ),
        ]
        let response = try await client.request(
            method: "POST",
            origin: XmlyClient.welfareOrigin,
            path: "\(Self.path)/rewardDuration/ts-\(timestamp)",
            json: payload,
            readOnly: false
        )
        return try validateResult(response)
    }

    /// 自动领取循环：持续领取直到服务端上限或余额不再增长，返回最新额度与原因说明
    public func refresh(enabled: Bool) async throws -> (quota: Quota, note: String) {
        var current = try await client.quota()
        lastMessage = ""
        guard enabled else { return (current, "") }

        var claimedRounds = 0
        for _ in 0..<Self.maxClaimsPerPass {
            let before = current.remainingSeconds
            do {
                _ = try await claim()
                claimedRounds += 1
                current = try await client.quota()
            } catch let error as XmlyException {
                lastMessage = error.message
                break
            } catch {
                lastMessage = "领取听时未完成，请稍后再试"
                break
            }
            if current.remainingSeconds <= before { break }
        }
        if claimedRounds > 0 && lastMessage.isEmpty {
            lastMessage = "已成功补充 \(claimedRounds) 次听时"
        }
        return (current, lastMessage)
    }

    private func validatedUid() throws -> String {
        guard let account = client.credentials else {
            throw XmlyException(code: "login_expired", message: "领取或查询听时需要有效的登录态", definitive: true)
        }
        let uid = account.uid
        guard !uid.isEmpty, uid.allSatisfy(\.isNumber), !uid.hasPrefix("0") else {
            throw XmlyException(code: "auth_required", message: "登录态缺少有效账号标识", definitive: true)
        }
        return uid
    }

    private func validateResult(_ response: [String: Any]) throws -> [String: Any] {
        guard let data = response["data"] as? [String: Any],
              let success = JSONHelpers.bool(data["success"]) else {
            throw XmlyException(code: "invalid_response", message: "福利响应缺少明确结果")
        }
        if !success {
            let candidates = [
                JSONHelpers.string(data["msg"]),
                JSONHelpers.string(data["message"]),
                JSONHelpers.string(response["msg"]),
            ]
            let reason = candidates.first(where: { !$0.isEmpty }) ?? "福利请求未成功，请在官方 App 检查"
            throw XmlyException(code: "reward_rejected", message: reason, definitive: true)
        }
        return data
    }
}
