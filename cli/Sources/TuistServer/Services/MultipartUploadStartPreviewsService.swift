import Foundation
import Mockable
import TuistHTTP
import TuistSimulator

@Mockable
public protocol MultipartUploadStartPreviewsServicing {
    func startPreviewsMultipartUpload(
        type: PreviewType,
        displayName: String,
        version: String?,
        buildVersion: String,
        bundleIdentifier: String?,
        supportedPlatforms: [DestinationType],
        gitBranch: String?,
        gitCommitSHA: String?,
        gitRef: String?,
        binaryId: String?,
        fullHandle: String,
        serverURL: URL,
        track: String?
    ) async throws -> AppBuildUpload
}

public enum MultipartUploadStartPreviewsServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)
    case conflict(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The app build could not be uploaded due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message), let .forbidden(message), let .unauthorized(message), let .conflict(message):
            return message
        }
    }
}

public final class MultipartUploadStartPreviewsService: MultipartUploadStartPreviewsServicing {
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

    public func startPreviewsMultipartUpload(
        type: PreviewType,
        displayName: String,
        version: String?,
        buildVersion: String,
        bundleIdentifier: String?,
        supportedPlatforms: [DestinationType],
        gitBranch: String?,
        gitCommitSHA: String?,
        gitRef: String?,
        binaryId: String?,
        fullHandle: String,
        serverURL: URL,
        track: String?
    ) async throws -> AppBuildUpload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let type: Operations.startPreviewsMultipartUpload.Input.Body.jsonPayload
            ._typePayload = switch type
        {
        case .appBundle:
            .app_bundle
        case .ipa:
            .ipa
        }
        let response = try await client.startPreviewsMultipartUpload(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                body: .json(
                    .init(
                        binary_id: binaryId,
                        build_version: buildVersion,
                        bundle_identifier: bundleIdentifier,
                        display_name: displayName,
                        git_branch: gitBranch,
                        git_commit_sha: gitCommitSHA,
                        git_ref: gitRef,
                        supported_platforms: supportedPlatforms.map(Components.Schemas.PreviewSupportedPlatform.init),
                        track: track,
                        _type: type,
                        version: version
                    )
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(appBuildUpload):
                return AppBuildUpload(
                    appBuildId: appBuildUpload.data.app_build_id,
                    uploadId: appBuildUpload.data.upload_id
                )
            }
        case let .undocumented(statusCode: statusCode, _):
            throw MultipartUploadStartPreviewsServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw MultipartUploadStartPreviewsServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw MultipartUploadStartPreviewsServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw MultipartUploadStartPreviewsServiceError.unauthorized(error.message)
            }
        case let .conflict(conflictResponse):
            switch conflictResponse.body {
            case let .json(error):
                throw MultipartUploadStartPreviewsServiceError.conflict(error.message)
            }
        }
    }
}
