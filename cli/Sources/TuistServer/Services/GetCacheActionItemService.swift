import Foundation
import Mockable
import TuistHTTP

@Mockable
public protocol GetCacheActionItemServicing {
    func getCacheActionItem(
        serverURL: URL,
        fullHandle: String,
        hash: String
    ) async throws -> ServerCacheActionItem
}

public enum GetCacheActionItemServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case notFound(String)
    case paymentRequired(String)
    case forbidden(String)
    case unauthorized(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The cache item could not be fetched due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message), let .paymentRequired(message), let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public final class GetCacheActionItemService: GetCacheActionItemServicing {
    private let fullHandleService: FullHandleServicing

    public convenience init() {
        self.init(fullHandleService: FullHandleService())
    }

    init(
        fullHandleService: FullHandleServicing
    ) {
        self.fullHandleService = fullHandleService
    }

    public func getCacheActionItem(
        serverURL: URL,
        fullHandle: String,
        hash: String
    ) async throws -> ServerCacheActionItem {
        let client = Client.authenticated(serverURL: serverURL)

        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.getCacheActionItem(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle:
                    handles.projectHandle,
                    hash: hash
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(cacheActionItem):
                return ServerCacheActionItem(cacheActionItem)
            }
        case let .code402(paymentRequiredResponse):
            switch paymentRequiredResponse.body {
            case let .json(error):
                throw GetCacheActionItemServiceError.paymentRequired(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetCacheActionItemServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw GetCacheActionItemServiceError.forbidden(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw GetCacheActionItemServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw GetCacheActionItemServiceError.unauthorized(error.message)
            }
        }
    }
}
