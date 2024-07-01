import Foundation
import Mockable
import TuistSupport

@Mockable
public protocol DownloadBuildServicing {
    func downloadBuild(
        _ buildId: String,
        serverURL: URL
    ) async throws -> String
}

public enum DownloadBuildServiceError: FatalError, Equatable {
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

public final class DownloadBuildService: DownloadBuildServicing {
    public init() {}

    public func downloadBuild(
        _ buildId: String,
        serverURL: URL
    ) async throws -> String {
        let client = Client.cloud(serverURL: serverURL)
        let response = try await client.downloadBuild(
            .init(
                path: .init(build_id: buildId)
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(build):
                return build.url
            }
        case let .undocumented(statusCode: statusCode, _):
            throw DownloadBuildServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw DownloadBuildServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw DownloadBuildServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DownloadBuildServiceError.unauthorized(error.message)
            }
        }
    }
}
