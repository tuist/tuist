import Foundation
import Mockable
import OpenAPIRuntime

/// The signed-in user's personal Claude and ChatGPT subscriptions. Only the signed-in Tuist app can manage them, and
/// only for users with the `ai` feature flag.
@Mockable
public protocol AISubscriptionsServicing: Sendable {
    func listAISubscriptions(serverURL: URL) async throws -> [ServerAISubscription]
    /// Saves the token `claude setup-token` prints.
    func connectClaudeSubscription(token: String, serverURL: URL) async throws -> [ServerAISubscription]
    func startChatGPTSubscriptionLogin(serverURL: URL) async throws -> ServerChatGPTLogin
    /// Returns whether the user approved the sign-in. Poll no faster than the login's interval.
    func pollChatGPTSubscriptionLogin(loginID: String, serverURL: URL) async throws -> Bool
    func cancelChatGPTSubscriptionLogin(loginID: String, serverURL: URL) async throws
    func disconnectAISubscription(
        provider: ServerAISubscription.Provider,
        serverURL: URL
    ) async throws -> [ServerAISubscription]
}

public enum AISubscriptionsServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    /// A failure the server explains, such as an invalid token or an expired sign-in.
    case server(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The AI subscriptions could not be updated due to an unknown Tuist response of \(statusCode)."
        case let .server(message):
            return message
        }
    }
}

public struct AISubscriptionsService: AISubscriptionsServicing {
    private let makeClient: @Sendable (URL) -> Client

    public init() {
        self.init(makeClient: { Client.authenticated(serverURL: $0) })
    }

    init(makeClient: @escaping @Sendable (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func listAISubscriptions(serverURL: URL) async throws -> [ServerAISubscription] {
        switch try await makeClient(serverURL).listAISubscriptions(.init()) {
        case let .ok(response): return try response.body.json.subscriptions.compactMap(ServerAISubscription.init)
        case let .unauthorized(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .forbidden(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .notFound(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .undocumented(statusCode, _): throw AISubscriptionsServiceError.unknownError(statusCode)
        }
    }

    public func connectClaudeSubscription(token: String, serverURL: URL) async throws -> [ServerAISubscription] {
        switch try await makeClient(serverURL).connectClaudeSubscription(.init(body: .json(.init(token: token)))) {
        case let .ok(response): return try response.body.json.subscriptions.compactMap(ServerAISubscription.init)
        case let .unauthorized(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .forbidden(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .notFound(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .unprocessableContent(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .serviceUnavailable(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .undocumented(statusCode, _): throw AISubscriptionsServiceError.unknownError(statusCode)
        }
    }

    public func startChatGPTSubscriptionLogin(serverURL: URL) async throws -> ServerChatGPTLogin {
        switch try await makeClient(serverURL).startChatGPTSubscriptionLogin(.init()) {
        case let .ok(response):
            let login = try response.body.json
            guard let verificationURL = URL(string: login.verification_url) else {
                throw AISubscriptionsServiceError.server("The server returned an invalid ChatGPT sign-in page.")
            }
            return ServerChatGPTLogin(
                loginID: login.login_id,
                userCode: login.user_code,
                verificationURL: verificationURL,
                interval: login.interval,
                expiresAt: login.expires_at
            )
        case let .unauthorized(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .forbidden(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .notFound(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .tooManyRequests(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .badGateway(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .serviceUnavailable(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .undocumented(statusCode, _): throw AISubscriptionsServiceError.unknownError(statusCode)
        }
    }

    public func pollChatGPTSubscriptionLogin(loginID: String, serverURL: URL) async throws -> Bool {
        switch try await makeClient(serverURL).pollChatGPTSubscriptionLogin(.init(body: .json(.init(login_id: loginID)))) {
        case let .ok(response): return try response.body.json.status == "connected"
        case let .unauthorized(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .forbidden(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .notFound(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .gone(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .badGateway(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .undocumented(statusCode, _): throw AISubscriptionsServiceError.unknownError(statusCode)
        }
    }

    public func cancelChatGPTSubscriptionLogin(loginID: String, serverURL: URL) async throws {
        switch try await makeClient(serverURL).cancelChatGPTSubscriptionLogin(.init(query: .init(login_id: loginID))) {
        case .noContent: return
        case let .unauthorized(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .forbidden(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .notFound(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .undocumented(statusCode, _): throw AISubscriptionsServiceError.unknownError(statusCode)
        }
    }

    public func disconnectAISubscription(
        provider: ServerAISubscription.Provider,
        serverURL: URL
    ) async throws -> [ServerAISubscription] {
        let providerPath: Operations.disconnectAISubscription.Input.Path.providerPayload = switch provider {
        case .claude: .claude
        case .chatgpt: .chatgpt
        }
        switch try await makeClient(serverURL).disconnectAISubscription(.init(path: .init(provider: providerPath))) {
        case let .ok(response): return try response.body.json.subscriptions.compactMap(ServerAISubscription.init)
        case let .unauthorized(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .forbidden(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .notFound(response): throw AISubscriptionsServiceError.server(try response.body.json.message)
        case let .undocumented(statusCode, _): throw AISubscriptionsServiceError.unknownError(statusCode)
        }
    }
}
