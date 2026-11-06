import Foundation

/// The connection state of one of the signed-in user's personal AI subscriptions.
public struct ServerAISubscription: Equatable, Hashable, Sendable, Identifiable {
    /// The providers this client can connect. Servers can add providers, which clients skip until they support them.
    public enum Provider: String, Sendable {
        case claude
        case chatgpt
    }

    public let provider: Provider
    public let isConnected: Bool
    public let updatedAt: Date?
    /// Whether the server can connect the provider.
    public let isLoginAvailable: Bool

    public var id: Provider {
        provider
    }

    public init(provider: Provider, isConnected: Bool, updatedAt: Date?, isLoginAvailable: Bool) {
        self.provider = provider
        self.isConnected = isConnected
        self.updatedAt = updatedAt
        self.isLoginAvailable = isLoginAvailable
    }

    /// `nil` for a provider this client doesn't support.
    init?(_ subscription: some AISubscriptionPayload) {
        guard let provider = Provider(rawValue: subscription.provider) else { return nil }
        self.init(
            provider: provider,
            isConnected: subscription.connected,
            updatedAt: subscription.updated_at,
            isLoginAvailable: subscription.login_available
        )
    }
}

// The generated subscription type of each operation that returns the subscriptions.
// swiftlint:disable identifier_name
protocol AISubscriptionPayload {
    var provider: String { get }
    var connected: Bool { get }
    var updated_at: Date? { get }
    var login_available: Bool { get }
}

// swiftlint:enable identifier_name

extension Operations.listAISubscriptions.Output.Ok.Body.jsonPayload.subscriptionsPayloadPayload: AISubscriptionPayload {}
extension Operations.connectClaudeSubscription.Output.Ok.Body.jsonPayload.subscriptionsPayloadPayload: AISubscriptionPayload {}
extension Operations.disconnectAISubscription.Output.Ok.Body.jsonPayload.subscriptionsPayloadPayload: AISubscriptionPayload {}

/// A pending ChatGPT device sign-in: the user enters `userCode` at `verificationURL`.
public struct ServerChatGPTLogin: Equatable, Sendable, Identifiable {
    public let loginID: String
    public let userCode: String
    public let verificationURL: URL
    /// The minimum number of seconds between polls.
    public let interval: Int
    public let expiresAt: Date

    public var id: String {
        loginID
    }

    public init(loginID: String, userCode: String, verificationURL: URL, interval: Int, expiresAt: Date) {
        self.loginID = loginID
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.interval = interval
        self.expiresAt = expiresAt
    }
}
