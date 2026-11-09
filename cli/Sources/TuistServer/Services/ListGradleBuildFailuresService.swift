import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

/// A failed Gradle task or configuration operation, with the failure message the Tuist Gradle plugin reported.
public struct ServerGradleBuildFailure: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let project: String
    public let target: String
    public let category: String
    public let startMs: Double
    public let durationMs: Double
    /// `nil` when the plugin that reported the build predates failure reporting, or the build reported more failures than
    /// the server keeps.
    public let message: String?
    public let messageTruncated: Bool

    public init(
        id: String,
        title: String,
        project: String,
        target: String,
        category: String,
        startMs: Double,
        durationMs: Double,
        message: String?,
        messageTruncated: Bool
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.target = target
        self.category = category
        self.startMs = startMs
        self.durationMs = durationMs
        self.message = message
        self.messageTruncated = messageTruncated
    }

    enum CodingKeys: String, CodingKey {
        case id, title, project, target, category, message
        case startMs = "start_ms"
        case durationMs = "duration_ms"
        case messageTruncated = "message_truncated"
    }
}

@Mockable
public protocol ListGradleBuildFailuresServicing: Sendable {
    /// Lists the failed steps of a Gradle build in start order, each with its reported failure message.
    func listGradleBuildFailures(
        fullHandle: String,
        serverURL: URL,
        buildId: String
    ) async throws -> [ServerGradleBuildFailure]
}

enum ListGradleBuildFailuresServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case badRequest(String)
    case forbidden(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not list the Gradle build failures due to an unknown Tuist response of \(statusCode)."
        case let .badRequest(message), let .forbidden(message), let .notFound(message):
            return message
        }
    }
}

public struct ListGradleBuildFailuresService: ListGradleBuildFailuresServicing {
    private static let maxSteps = 50
    private let fullHandleService: FullHandleServicing

    public init() {
        self.init(fullHandleService: FullHandleService())
    }

    init(fullHandleService: FullHandleServicing) {
        self.fullHandleService = fullHandleService
    }

    public func listGradleBuildFailures(
        fullHandle: String,
        serverURL: URL,
        buildId: String
    ) async throws -> [ServerGradleBuildFailure] {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let steps = try await failedSteps(
            client: client,
            path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle, build_id: buildId)
        )

        var failures: [ServerGradleBuildFailure] = []
        for step in steps {
            let detail = try await stepDetail(
                client: client,
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    build_id: buildId,
                    step_id: step.id
                )
            )
            failures.append(ServerGradleBuildFailure(
                id: step.id,
                title: step.title,
                project: step.project,
                target: step.target,
                category: step.category,
                startMs: step.start_ms,
                durationMs: step.duration_ms,
                message: detail.log,
                messageTruncated: detail.log_truncated
            ))
        }
        return failures
    }

    /// One page of failed steps: the server keeps failure messages for at most 32 steps per build, and Gradle stops at
    /// the first failure unless the build runs with --continue.
    private func failedSteps(
        client: Client,
        path: Operations.listGradleBuildSteps.Input.Path
    ) async throws -> [Operations.listGradleBuildSteps.Output.Ok.Body.jsonPayload.stepsPayloadPayload] {
        let response = try await client.listGradleBuildSteps(
            .init(path: path, query: .init(page: 1, page_size: Self.maxSteps, status: .failure, sort_by: .start_ms))
        )
        switch response {
        case let .ok(ok):
            switch ok.body {
            case let .json(json): return json.steps
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error): throw ListGradleBuildFailuresServiceError.badRequest(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error): throw ListGradleBuildFailuresServiceError.forbidden(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error): throw ListGradleBuildFailuresServiceError.notFound(error.message)
            }
        case let .tooManyRequests(tooManyRequests):
            throw AuthorizationThrottledError(
                retryAfterSeconds: tooManyRequests.headers.retry_hyphen_after.flatMap(Int.init)
            )
        case let .undocumented(statusCode: statusCode, _):
            throw ListGradleBuildFailuresServiceError.unknownError(statusCode)
        }
    }

    private func stepDetail(
        client: Client,
        path: Operations.getGradleBuildStep.Input.Path
    ) async throws -> Operations.getGradleBuildStep.Output.Ok.Body.jsonPayload {
        switch try await client.getGradleBuildStep(.init(path: path)) {
        case let .ok(ok):
            switch ok.body {
            case let .json(json): return json
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error): throw ListGradleBuildFailuresServiceError.badRequest(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error): throw ListGradleBuildFailuresServiceError.forbidden(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error): throw ListGradleBuildFailuresServiceError.notFound(error.message)
            }
        case let .tooManyRequests(tooManyRequests):
            throw AuthorizationThrottledError(
                retryAfterSeconds: tooManyRequests.headers.retry_hyphen_after.flatMap(Int.init)
            )
        case let .undocumented(statusCode: statusCode, _):
            throw ListGradleBuildFailuresServiceError.unknownError(statusCode)
        }
    }
}
