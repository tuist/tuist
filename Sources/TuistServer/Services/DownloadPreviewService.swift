import Foundation
import Mockable
import TuistSupport

@Mockable
public protocol DownloadPreviewServicing {
    func downloadPreview(
        _ previewId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws -> String
}

public enum DownloadPreviewServiceError: FatalError, Equatable {
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

public final class DownloadPreviewService: DownloadPreviewServicing {
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

    public func downloadPreview(
        _ previewId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws -> String {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.downloadPreview(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    preview_id: previewId
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
            throw DownloadPreviewServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw DownloadPreviewServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw DownloadPreviewServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DownloadPreviewServiceError.unauthorized(error.message)
            }
        }
    }
}
