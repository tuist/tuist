import Foundation
import Mockable
import OpenAPIRuntime

/// The signed-in user's notification rules (`/api/me/notification-rules`). Only the signed-in Tuist app can call
/// these endpoints.
@Mockable
public protocol NotificationRulesServicing: Sendable {
    func listRules(serverURL: URL) async throws -> [ServerNotificationRule]
    func createRule(_ rule: ServerNotificationRule, serverURL: URL) async throws -> ServerNotificationRule
    /// Saves every field of `rule` except its event, which can't change.
    func updateRule(_ rule: ServerNotificationRule, serverURL: URL) async throws -> ServerNotificationRule
    func deleteRule(id: String, serverURL: URL) async throws
    /// Values the user can pick for `event`'s conditions in a project, keyed by condition, such as `track` and
    /// `git_branch`.
    func conditionOptions(event: String, projectFullHandle: String, serverURL: URL) async throws -> [String: [String]]
}

public enum NotificationRulesServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case invalid(String)
    case tooManyRequests(String)
    /// The server predates notification rules.
    case unsupported

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The notification rules could not be updated due to an unknown Tuist response of \(statusCode)."
        case .unsupported:
            return "This Tuist server doesn't offer notification rules yet. Ask its administrator to update it."
        case let .unauthorized(message), let .forbidden(message), let .notFound(message), let .invalid(message),
             let .tooManyRequests(message):
            return message
        }
    }
}

public struct NotificationRulesService: NotificationRulesServicing {
    private let makeClient: @Sendable (URL) -> Client

    public init() {
        self.init(makeClient: { Client.authenticated(serverURL: $0) })
    }

    init(makeClient: @escaping @Sendable (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func listRules(serverURL: URL) async throws -> [ServerNotificationRule] {
        switch try await makeClient(serverURL).listNotificationRules(.init()) {
        case let .ok(response):
            return try response.body.json.rules
                .map { try NotificationRulePayload.convert($0, to: NotificationRulePayload.self).rule }
        case let .unauthorized(response):
            throw NotificationRulesServiceError.unauthorized(try response.body.json.message)
        case let .forbidden(response):
            throw NotificationRulesServiceError.forbidden(try response.body.json.message)
        case .undocumented(statusCode: 404, _):
            throw NotificationRulesServiceError.unsupported
        case let .undocumented(statusCode, _):
            throw NotificationRulesServiceError.unknownError(statusCode)
        }
    }

    public func createRule(_ rule: ServerNotificationRule, serverURL: URL) async throws -> ServerNotificationRule {
        let body: Operations.createNotificationRule.Input.Body.jsonPayload = try NotificationRulePayload.convert(
            NotificationRulePayload(rule, includingEvent: true)
        )
        switch try await makeClient(serverURL).createNotificationRule(.init(body: .json(body))) {
        case let .created(response):
            return try NotificationRulePayload.convert(response.body.json, to: NotificationRulePayload.self).rule
        case let .badRequest(response):
            throw NotificationRulesServiceError.invalid(try response.body.json.message)
        case let .unprocessableContent(response):
            throw NotificationRulesServiceError.invalid(try response.body.json.message)
        case let .unauthorized(response):
            throw NotificationRulesServiceError.unauthorized(try response.body.json.message)
        case let .forbidden(response):
            throw NotificationRulesServiceError.forbidden(try response.body.json.message)
        case let .tooManyRequests(response):
            throw NotificationRulesServiceError.tooManyRequests(try response.body.json.message)
        case .undocumented(statusCode: 404, _):
            throw NotificationRulesServiceError.unsupported
        case let .undocumented(statusCode, _):
            throw NotificationRulesServiceError.unknownError(statusCode)
        }
    }

    public func updateRule(_ rule: ServerNotificationRule, serverURL: URL) async throws -> ServerNotificationRule {
        let body: Operations.updateNotificationRule.Input.Body.jsonPayload = try NotificationRulePayload.convert(
            NotificationRulePayload(rule, includingEvent: false)
        )
        switch try await makeClient(serverURL).updateNotificationRule(.init(path: .init(id: rule.id), body: .json(body))) {
        case let .ok(response):
            return try NotificationRulePayload.convert(response.body.json, to: NotificationRulePayload.self).rule
        case let .badRequest(response):
            throw NotificationRulesServiceError.invalid(try response.body.json.message)
        case let .notFound(response):
            throw NotificationRulesServiceError.notFound(try response.body.json.message)
        case let .unauthorized(response):
            throw NotificationRulesServiceError.unauthorized(try response.body.json.message)
        case let .forbidden(response):
            throw NotificationRulesServiceError.forbidden(try response.body.json.message)
        case let .tooManyRequests(response):
            throw NotificationRulesServiceError.tooManyRequests(try response.body.json.message)
        case let .undocumented(statusCode, _):
            throw NotificationRulesServiceError.unknownError(statusCode)
        }
    }

    public func deleteRule(id: String, serverURL: URL) async throws {
        switch try await makeClient(serverURL).deleteNotificationRule(.init(path: .init(id: id))) {
        // Already deleted, for example from another device.
        case .noContent, .notFound:
            return
        case let .unauthorized(response):
            throw NotificationRulesServiceError.unauthorized(try response.body.json.message)
        case let .forbidden(response):
            throw NotificationRulesServiceError.forbidden(try response.body.json.message)
        case let .tooManyRequests(response):
            throw NotificationRulesServiceError.tooManyRequests(try response.body.json.message)
        case let .undocumented(statusCode, _):
            throw NotificationRulesServiceError.unknownError(statusCode)
        }
    }

    public func conditionOptions(
        event: String,
        projectFullHandle: String,
        serverURL: URL
    ) async throws -> [String: [String]] {
        let handles = projectFullHandle.split(separator: "/", maxSplits: 1).map(String.init)
        guard handles.count == 2 else { return [:] }
        let response = try await makeClient(serverURL).listNotificationConditionOptions(
            .init(path: .init(event: event, account_handle: handles[0], project_handle: handles[1]))
        )
        switch response {
        case let .ok(response):
            return try response.body.json.options.additionalProperties
        // The project can't get these notifications, or the server predates them: nothing to suggest.
        case .notFound, .undocumented(statusCode: 404, _):
            return [:]
        case let .unauthorized(response):
            throw NotificationRulesServiceError.unauthorized(try response.body.json.message)
        case let .forbidden(response):
            throw NotificationRulesServiceError.forbidden(try response.body.json.message)
        case let .undocumented(statusCode, _):
            throw NotificationRulesServiceError.unknownError(statusCode)
        }
    }
}
