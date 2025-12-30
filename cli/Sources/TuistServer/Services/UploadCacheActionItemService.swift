import Foundation
import Mockable
import TuistHTTP

@Mockable
public protocol UploadCacheActionItemServicing {
    func uploadCacheActionItem(
        serverURL: URL,
        fullHandle: String,
        hash: String
    ) async throws -> ServerCacheActionItem
}

public enum UploadCacheActionItemServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case notFound(String)
    case paymentRequired(String)
    case forbidden(String)
    case unauthorized(String)
    case badRequest(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The cache item could not be uploaded due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message), let .paymentRequired(message), let .forbidden(message), let .unauthorized(message),
             let .badRequest(message):
            return message
        }
    }
}

public final class UploadCacheActionItemService: UploadCacheActionItemServicing {
    private let fullHandleService: FullHandleServicing

    public convenience init() {
        self.init(fullHandleService: FullHandleService())
    }

    init(
        fullHandleService: FullHandleServicing
    ) {
        self.fullHandleService = fullHandleService
    }

    public func uploadCacheActionItem(
        serverURL: URL,
        fullHandle: String,
        hash: String
    ) async throws -> ServerCacheActionItem {
        let client = Client.authenticated(serverURL: serverURL)

        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.uploadCacheActionItem(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle:
                    handles.projectHandle
                ),
                body: .json(
                    .init(
                        hash: hash
                    )
                )
            )
        )

        switch response {
        case let .created(createdResponse):
            switch createdResponse.body {
            case let .json(cacheActionItem):
                return ServerCacheActionItem(cacheActionItem)
            }
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(cacheActionItem):
                return ServerCacheActionItem(cacheActionItem)
            }
        case let .code402(paymentRequiredResponse):
            switch paymentRequiredResponse.body {
            case let .json(error):
                throw UploadCacheActionItemServiceError.paymentRequired(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw UploadCacheActionItemServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw UploadCacheActionItemServiceError.forbidden(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw UploadCacheActionItemServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw UploadCacheActionItemServiceError.unauthorized(error.message)
            }
        case let .badRequest(badRequestResponse):
            switch badRequestResponse.body {
            case let .json(error):
                throw UploadCacheActionItemServiceError.badRequest(error.message)
            }
        }
    }
}
