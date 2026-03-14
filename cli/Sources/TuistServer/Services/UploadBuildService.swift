import FileSystem
import Foundation
import Mockable
import OpenAPIRuntime
import Path
import TuistHTTP

@Mockable
public protocol UploadBuildServicing {
    func uploadBuild(
        buildId: String,
        fullHandle: String,
        serverURL: URL,
        filePath: AbsolutePath
    ) async throws
}

enum UploadBuildServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)
    case notFound(String)
    case unauthorized(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return
                "The upload could not be completed due to an unknown server response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message):
            return message
        }
    }
}

public struct UploadBuildService: UploadBuildServicing {
    private let fullHandleService: FullHandleServicing
    private let multipartUploadArtifactService: MultipartUploadArtifactServicing

    public init(
        fullHandleService: FullHandleServicing = FullHandleService(),
        multipartUploadArtifactService: MultipartUploadArtifactServicing = MultipartUploadArtifactService()
    ) {
        self.fullHandleService = fullHandleService
        self.multipartUploadArtifactService = multipartUploadArtifactService
    }

    public func uploadBuild(
        buildId: String,
        fullHandle: String,
        serverURL: URL,
        filePath: AbsolutePath
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let accountHandle = handles.accountHandle
        let projectHandle = handles.projectHandle

        let uploadId = try await startMultipartUpload(
            client: client,
            accountHandle: accountHandle,
            projectHandle: projectHandle,
            buildId: buildId
        )

        let parts = try await multipartUploadArtifactService.multipartUploadArtifact(
            artifactPath: filePath,
            generateUploadURL: { part in
                try await generatePartURL(
                    client: client,
                    accountHandle: accountHandle,
                    projectHandle: projectHandle,
                    buildId: buildId,
                    uploadId: uploadId,
                    part: part
                )
            },
            updateProgress: { _ in }
        )

        try await completeMultipartUpload(
            client: client,
            accountHandle: accountHandle,
            projectHandle: projectHandle,
            buildId: buildId,
            uploadId: uploadId,
            parts: parts
        )
    }

    private func startMultipartUpload(
        client: Client,
        accountHandle: String,
        projectHandle: String,
        buildId: String
    ) async throws -> String {
        let response = try await client.startBuildsMultipartUpload(
            path: .init(
                account_handle: accountHandle,
                project_handle: projectHandle
            ),
            body: .json(.init(build_id: buildId))
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(upload):
                return upload.data.upload_id
            }
        case let .unauthorized(unauthorizedResponse):
            switch unauthorizedResponse.body {
            case let .json(error):
                throw UploadBuildServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw UploadBuildServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw UploadBuildServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw UploadBuildServiceError.unknownError(statusCode)
        }
    }

    private func generatePartURL(
        client: Client,
        accountHandle: String,
        projectHandle: String,
        buildId: String,
        uploadId: String,
        part: MultipartUploadArtifactPart
    ) async throws -> String {
        let response = try await client.generateBuildsMultipartUploadURL(
            path: .init(
                account_handle: accountHandle,
                project_handle: projectHandle
            ),
            body: .json(.init(
                build_id: buildId,
                multipart_upload_part: .init(
                    content_length: part.contentLength,
                    part_number: part.number,
                    upload_id: uploadId
                )
            ))
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(urlResponse):
                return urlResponse.data.url
            }
        case let .unauthorized(unauthorizedResponse):
            switch unauthorizedResponse.body {
            case let .json(error):
                throw UploadBuildServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw UploadBuildServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw UploadBuildServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw UploadBuildServiceError.unknownError(statusCode)
        }
    }

    private func completeMultipartUpload(
        client: Client,
        accountHandle: String,
        projectHandle: String,
        buildId: String,
        uploadId: String,
        parts: [(etag: String, partNumber: Int)]
    ) async throws {
        let response = try await client.completeBuildsMultipartUpload(
            path: .init(
                account_handle: accountHandle,
                project_handle: projectHandle
            ),
            body: .json(.init(
                build_id: buildId,
                multipart_upload_parts: .init(
                    parts: parts.map {
                        .init(etag: $0.etag, part_number: $0.partNumber)
                    },
                    upload_id: uploadId
                )
            ))
        )

        switch response {
        case .ok:
            return
        case let .unauthorized(unauthorizedResponse):
            switch unauthorizedResponse.body {
            case let .json(error):
                throw UploadBuildServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw UploadBuildServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw UploadBuildServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw UploadBuildServiceError.unknownError(statusCode)
        }
    }
}
