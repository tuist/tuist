import Foundation
import Mockable
import TuistHTTP

@Mockable
public protocol CreateShardSessionServicing {
    func createShardSession(
        fullHandle: String,
        serverURL: URL,
        sessionId: String,
        modules: [String]?,
        testSuites: [String]?,
        shardMin: Int?,
        shardMax: Int?,
        shardTotal: Int?,
        shardMaxDuration: Int?,
        granularity: String
    ) async throws -> ServerShardSession
}

public enum CreateShardSessionServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case forbidden(String)
    case notFound(String)
    case unauthorized(String)
    case badRequest(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to create shard session due to an unknown server response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message),
             let .badRequest(message):
            return message
        }
    }
}

public struct CreateShardSessionService: CreateShardSessionServicing {
    private let fullHandleService: FullHandleServicing

    public init(
        fullHandleService: FullHandleServicing = FullHandleService()
    ) {
        self.fullHandleService = fullHandleService
    }

    public func createShardSession(
        fullHandle: String,
        serverURL: URL,
        sessionId: String,
        modules: [String]?,
        testSuites: [String]?,
        shardMin: Int?,
        shardMax: Int?,
        shardTotal: Int?,
        shardMaxDuration: Int?,
        granularity: String
    ) async throws -> ServerShardSession {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let granularityPayload: Operations.createShardSession.Input.Body.jsonPayload.granularityPayload =
            granularity == "suite" ? .suite : .module

        let response = try await client.createShardSession(
            path: .init(
                account_handle: handles.accountHandle,
                project_handle: handles.projectHandle
            ),
            body: .json(
                .init(
                    granularity: granularityPayload,
                    modules: modules,
                    session_id: sessionId,
                    shard_max: shardMax,
                    shard_max_duration: shardMaxDuration,
                    shard_min: shardMin,
                    shard_total: shardTotal,
                    test_suites: testSuites
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(session):
                return ServerShardSession(
                    sessionId: session.session_id,
                    shardCount: session.shard_count,
                    shards: session.shards.map { shard in
                        ServerShardAssignment(
                            index: shard.index,
                            testTargets: shard.test_targets,
                            estimatedDurationMs: shard.estimated_duration_ms
                        )
                    },
                    uploadId: session.upload_id
                )
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw CreateShardSessionServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw CreateShardSessionServiceError.unauthorized(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw CreateShardSessionServiceError.notFound(error.message)
            }
        case let .badRequest(badRequestResponse):
            switch badRequestResponse.body {
            case let .json(error):
                throw CreateShardSessionServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode, _):
            throw CreateShardSessionServiceError.unknownError(statusCode)
        }
    }
}
