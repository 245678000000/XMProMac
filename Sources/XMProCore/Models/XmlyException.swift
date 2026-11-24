import Foundation

/// 喜马拉雅协议与本地存储的统一业务异常
public struct XmlyException: Error, LocalizedError, Equatable, Sendable {
    public let code: String
    public let message: String
    public let retryAfterSeconds: TimeInterval?
    public let definitive: Bool

    public init(
        code: String,
        message: String,
        retryAfterSeconds: TimeInterval? = nil,
        definitive: Bool = false
    ) {
        self.code = code
        self.message = message
        self.retryAfterSeconds = retryAfterSeconds
        self.definitive = definitive
    }

    public var errorDescription: String? { message }
}
