import Foundation
import Mockable
import TuistSupport

@Mockable
public protocol MultipartUploadStartAppBuildsServicing {
    func startAppBuildsMultipartUpload(
        fullHandle: String,
        serverURL: URL
    ) async throws -> AppBuildUpload
}

public enum MultipartUploadStartAppBuildsServiceError: FatalError, Equatable {
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
            return "The app build could not be uploaded due to an unknown Tuist Cloud response of \(statusCode)."
        case let .notFound(message), let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public final class MultipartUploadStartAppBuildsService: MultipartUploadStartAppBuildsServicing {
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

    public func startAppBuildsMultipartUpload(
        fullHandle: String,
        serverURL: URL
    ) async throws -> AppBuildUpload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.startAppBuildsMultipartUpload(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(appBuild):
                return AppBuildUpload(
                    appBuildId: appBuild.data.app_build_id,
                    uploadId: appBuild.data.upload_id
                )
            }
        case let .undocumented(statusCode: statusCode, _):
            throw MultipartUploadStartAppBuildsServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw MultipartUploadStartAppBuildsServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw MultipartUploadStartAppBuildsServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw MultipartUploadStartAppBuildsServiceError.unauthorized(error.message)
            }
        }
    }
}
