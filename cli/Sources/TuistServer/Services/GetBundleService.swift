import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

@Mockable
public protocol GetBundleServicing {
    func getBundle(
        fullHandle: String,
        bundleId: String,
        serverURL: URL
    ) async throws -> Components.Schemas.Bundle
}

enum GetBundleServiceError: LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)
    case unprocessable(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not get the bundle due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message), let .unprocessable(message):
            return message
        }
    }
}

public final class GetBundleService: GetBundleServicing {
    private let fullHandleService: FullHandleServicing

    public convenience init() {
        self.init(
            fullHandleService: FullHandleService()
        )
    }

    init(
        fullHandleService: FullHandleServicing
    ) {
        self.fullHandleService = fullHandleService
    }

    public func getBundle(
        fullHandle: String,
        bundleId: String,
        serverURL: URL
    ) async throws -> Components.Schemas.Bundle {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.getBundle(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    bundle_id: bundleId
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(bundle):
                return bundle
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw GetBundleServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw GetBundleServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw GetBundleServiceError.unauthorized(error.message)
            }
        case let .unprocessableContent(unprocessable):
            switch unprocessable.body {
            case let .json(error):
                throw GetBundleServiceError.unprocessable(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetBundleServiceError.unknownError(statusCode)
        }
    }
}
