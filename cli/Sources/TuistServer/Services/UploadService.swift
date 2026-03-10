import FileSystem
import Foundation
import Mockable
import OpenAPIRuntime
import Path
import TuistHTTP
import TuistSupport

public enum UploadPurpose: String {
    case build = "build"
}

@Mockable
public protocol UploadServicing {
    func upload(
        id: String,
        fullHandle: String,
        serverURL: URL,
        filePath: AbsolutePath,
        purpose: UploadPurpose
    ) async throws
}

enum UploadServiceError: LocalizedError {
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

public struct UploadService: UploadServicing {
    private let fullHandleService: FullHandleServicing
    private let multipartUploadArtifactService: MultipartUploadArtifactServicing

    public init(
        fullHandleService: FullHandleServicing = FullHandleService(),
        multipartUploadArtifactService: MultipartUploadArtifactServicing = MultipartUploadArtifactService()
    ) {
        self.fullHandleService = fullHandleService
        self.multipartUploadArtifactService = multipartUploadArtifactService
    }

    public func upload(
        id: String,
        fullHandle: String,
        serverURL: URL,
        filePath: AbsolutePath,
        purpose: UploadPurpose
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let accountHandle = handles.accountHandle
        let projectHandle = handles.projectHandle

        let uploadId = try await startMultipartUpload(
            client: client,
            id: id,
            accountHandle: accountHandle,
            projectHandle: projectHandle,
            purpose: purpose
        )

        let parts = try await multipartUploadArtifactService.multipartUploadArtifact(
            artifactPath: filePath,
            generateUploadURL: { part in
                try await generatePartURL(
                    client: client,
                    id: id,
                    accountHandle: accountHandle,
                    projectHandle: projectHandle,
                    uploadId: uploadId,
                    part: part,
                    purpose: purpose
                )
            },
            updateProgress: { _ in }
        )

        try await completeMultipartUpload(
            client: client,
            id: id,
            accountHandle: accountHandle,
            projectHandle: projectHandle,
            uploadId: uploadId,
            parts: parts,
            purpose: purpose
        )
    }

    private func startMultipartUpload(
        client: Client,
        id: String,
        accountHandle: String,
        projectHandle: String,
        purpose: UploadPurpose
    ) async throws -> String {
        let response = try await client.startUploadsMultipartUpload(
            path: .init(
                account_handle: accountHandle,
                project_handle: projectHandle
            ),
            body: .json(buildStartBody(id: id, purpose: purpose))
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
                throw UploadServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw UploadServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw UploadServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw UploadServiceError.unknownError(statusCode)
        }
    }

    private func generatePartURL(
        client: Client,
        id: String,
        accountHandle: String,
        projectHandle: String,
        uploadId: String,
        part: MultipartUploadArtifactPart,
        purpose: UploadPurpose
    ) async throws -> String {
        let response = try await client.generateUploadsMultipartUploadURL(
            path: .init(
                account_handle: accountHandle,
                project_handle: projectHandle
            ),
            body: .json(buildGenerateURLBody(id: id, uploadId: uploadId, part: part, purpose: purpose))
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
                throw UploadServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw UploadServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw UploadServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw UploadServiceError.unknownError(statusCode)
        }
    }

    private func completeMultipartUpload(
        client: Client,
        id: String,
        accountHandle: String,
        projectHandle: String,
        uploadId: String,
        parts: [(etag: String, partNumber: Int)],
        purpose: UploadPurpose
    ) async throws {
        let response = try await client.completeUploadsMultipartUpload(
            path: .init(
                account_handle: accountHandle,
                project_handle: projectHandle
            ),
            body: .json(buildCompleteBody(id: id, uploadId: uploadId, parts: parts, purpose: purpose))
        )

        switch response {
        case .ok:
            return
        case let .unauthorized(unauthorizedResponse):
            switch unauthorizedResponse.body {
            case let .json(error):
                throw UploadServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw UploadServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw UploadServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw UploadServiceError.unknownError(statusCode)
        }
    }

    private func buildStartBody(
        id: String,
        purpose: UploadPurpose
    ) -> Operations.startUploadsMultipartUpload.Input.Body.jsonPayload {
        switch purpose {
        case .build:
            return .init(build_id: id, purpose: .build)
        }
    }

    private func buildGenerateURLBody(
        id: String,
        uploadId: String,
        part: MultipartUploadArtifactPart,
        purpose: UploadPurpose
    ) -> Operations.generateUploadsMultipartUploadURL.Input.Body.jsonPayload {
        switch purpose {
        case .build:
            return .init(
                build_id: id,
                multipart_upload_part: .init(
                    content_length: part.contentLength,
                    part_number: part.number,
                    upload_id: uploadId
                ),
                purpose: .build
            )
        }
    }

    private func buildCompleteBody(
        id: String,
        uploadId: String,
        parts: [(etag: String, partNumber: Int)],
        purpose: UploadPurpose
    ) -> Operations.completeUploadsMultipartUpload.Input.Body.jsonPayload {
        switch purpose {
        case .build:
            return .init(
                build_id: id,
                multipart_upload_parts: .init(
                    parts: parts.map {
                        .init(etag: $0.etag, part_number: $0.partNumber)
                    },
                    upload_id: uploadId
                ),
                purpose: .build
            )
        }
    }
}
