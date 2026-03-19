import Foundation
import Mockable
import TuistHTTP

@Mockable
public protocol GetShardServicing {
    func getShard(
        fullHandle: String,
        serverURL: URL,
        reference: String,
        shardIndex: Int
    ) async throws -> Components.Schemas.Shard
}

public enum GetShardServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case forbidden(String)
    case notFound(String)
    case unauthorized(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to get shard due to an unknown server response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message):
            return message
        }
    }
}

public struct GetShardService: GetShardServicing {
    private let fullHandleService: FullHandleServicing

    public init(
        fullHandleService: FullHandleServicing = FullHandleService()
    ) {
        self.fullHandleService = fullHandleService
    }

    public func getShard(
        fullHandle: String,
        serverURL: URL,
        reference: String,
        shardIndex: Int
    ) async throws -> Components.Schemas.Shard {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.getShard(
            path: .init(
                account_handle: handles.accountHandle,
                project_handle: handles.projectHandle,
                reference: reference,
                shard_index: shardIndex
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(shard):
                return shard
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw GetShardServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw GetShardServiceError.unauthorized(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw GetShardServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode, _):
            throw GetShardServiceError.unknownError(statusCode)
        }
    }
}
