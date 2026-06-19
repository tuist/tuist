import Foundation
import Mockable
import TuistHTTP

@Mockable
public protocol CreateShardPlanServicing {
    func createShardPlan(
        fullHandle: String,
        serverURL: URL,
        reference: String,
        modules: [String]?,
        testSuites: [String]?,
        shardMin: Int?,
        shardMax: Int?,
        shardTotal: Int?,
        shardMaxDuration: Int?,
        shardGranularity: Components.Schemas.CreateShardPlanParams.granularityPayload,
        buildRunId: String?
    ) async throws -> Components.Schemas.ShardPlan
}

public enum CreateShardPlanServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case forbidden(String)
    case notFound(String)
    case unauthorized(String)
    case badRequest(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to create shard plan due to an unknown server response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message),
             let .badRequest(message):
            return message
        }
    }
}

public struct CreateShardPlanService: CreateShardPlanServicing {
    private let fullHandleService: FullHandleServicing

    public init(
        fullHandleService: FullHandleServicing = FullHandleService()
    ) {
        self.fullHandleService = fullHandleService
    }

    public func createShardPlan(
        fullHandle: String,
        serverURL: URL,
        reference: String,
        modules: [String]?,
        testSuites: [String]?,
        shardMin: Int?,
        shardMax: Int?,
        shardTotal: Int?,
        shardMaxDuration: Int?,
        shardGranularity: Components.Schemas.CreateShardPlanParams.granularityPayload,
        buildRunId: String?
    ) async throws -> Components.Schemas.ShardPlan {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.createShardPlan(
            path: .init(
                account_handle: handles.accountHandle,
                project_handle: handles.projectHandle
            ),
            body: .json(
                .init(
                    build_run_id: buildRunId,
                    granularity: .init(rawValue: shardGranularity.rawValue),
                    modules: modules,
                    reference: reference,
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
                return session
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw CreateShardPlanServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw CreateShardPlanServiceError.unauthorized(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw CreateShardPlanServiceError.notFound(error.message)
            }
        case let .badRequest(badRequestResponse):
            switch badRequestResponse.body {
            case let .json(error):
                throw CreateShardPlanServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode, _):
            throw CreateShardPlanServiceError.unknownError(statusCode)
        }
    }
}
