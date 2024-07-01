import Foundation
import Mockable
import TuistSupport

@Mockable
public protocol MultipartUploadGenerateURLAppBuildsServicing {
    func uploadAppBuilds(
        _ appBuildId: String,
        partNumber: Int,
        uploadId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws -> String
}

public enum MultipartUploadGenerateURLAppBuildsServiceError: FatalError, Equatable {
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
            return "The generation of a multi-part upload URL failed due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message), let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public final class MultipartUploadGenerateURLAppBuildsService: MultipartUploadGenerateURLAppBuildsServicing {
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

    public func uploadAppBuilds(
        _ appBuildId: String,
        partNumber: Int,
        uploadId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws -> String {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.generateAppBuildsMultipartUploadURL(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                body: .json(
                    .init(
                        app_build_id: appBuildId,
                        multipart_upload_part: .init(
                            part_number: partNumber,
                            upload_id: uploadId
                        )
                    )
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(cacheArtifact):
                return cacheArtifact.data.url
            }
        case let .undocumented(statusCode: statusCode, _):
            throw MultipartUploadGenerateURLAppBuildsServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw MultipartUploadGenerateURLAppBuildsServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw MultipartUploadGenerateURLAppBuildsServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw MultipartUploadGenerateURLAppBuildsServiceError.unauthorized(error.message)
            }
        }
    }
}
