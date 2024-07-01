import Foundation
import Mockable
import TuistSupport

@Mockable
public protocol DownloadAppBuildServicing {
    func downloadAppBuild(
        _ appBuildId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws -> String
}

public enum DownloadAppBuildServiceError: FatalError, Equatable {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    public var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .notFound, .forbidden, .unauthorized:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The build could not be uploaded due to an unknown Tuist Cloud response of \(statusCode)."
        case let .notFound(message), let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public final class DownloadAppBuildService: DownloadAppBuildServicing {
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

    public func downloadAppBuild(
        _ appBuildId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws -> String {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.downloadAppBuild(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    app_build_id: appBuildId
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(build):
                return build.url
            }
        case let .undocumented(statusCode: statusCode, _):
            throw DownloadAppBuildServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw DownloadAppBuildServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw DownloadAppBuildServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DownloadAppBuildServiceError.unauthorized(error.message)
            }
        }
    }
}
