import Foundation
import Mockable
import TuistHTTP

@Mockable
public protocol GetShardAssignmentServicing {
    func getShardAssignment(
        fullHandle: String,
        serverURL: URL,
        planId: String,
        shardIndex: Int
    ) async throws -> ShardAssignmentResult
}

public struct ShardAssignmentResult: Equatable, Sendable {
    public let testTargets: [String]
    public let xctestrunDownloadURL: String
    public let bundleDownloadURL: String

    public init(
        testTargets: [String],
        xctestrunDownloadURL: String,
        bundleDownloadURL: String
    ) {
        self.testTargets = testTargets
        self.xctestrunDownloadURL = xctestrunDownloadURL
        self.bundleDownloadURL = bundleDownloadURL
    }
}

public enum GetShardAssignmentServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case forbidden(String)
    case notFound(String)
    case unauthorized(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to get shard assignment due to an unknown server response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message):
            return message
        }
    }
}

public struct GetShardAssignmentService: GetShardAssignmentServicing {
    private let fullHandleService: FullHandleServicing

    public init(
        fullHandleService: FullHandleServicing = FullHandleService()
    ) {
        self.fullHandleService = fullHandleService
    }

    public func getShardAssignment(
        fullHandle: String,
        serverURL: URL,
        planId: String,
        shardIndex: Int
    ) async throws -> ShardAssignmentResult {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.getShardAssignment(
            path: .init(
                account_handle: handles.accountHandle,
                project_handle: handles.projectHandle,
                session_id: planId,
                shard_index: shardIndex
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(assignment):
                return ShardAssignmentResult(
                    testTargets: assignment.test_targets,
                    xctestrunDownloadURL: assignment.xctestrun_download_url,
                    bundleDownloadURL: assignment.bundle_download_url
                )
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw GetShardAssignmentServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw GetShardAssignmentServiceError.unauthorized(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw GetShardAssignmentServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode, _):
            throw GetShardAssignmentServiceError.unknownError(statusCode)
        }
    }
}
