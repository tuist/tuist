#if canImport(TuistXCActivityLog)
    import Foundation
    import Mockable
    import OpenAPIRuntime
    import Path
    import TuistSupport
    import TuistHTTP

    @Mockable
    public protocol UploadBuildArchiveServicing {
        func uploadBuildArchive(
            id: String,
            fullHandle: String,
            serverURL: URL,
            archivePath: AbsolutePath,
            contentLength: Int
        ) async throws -> ServerUpload
    }

    enum UploadBuildArchiveServiceError: LocalizedError {
        case unknownError(Int)
        case forbidden(String)
        case notFound(String)
        case unauthorized(String)
        case badRequest(String)
        case uploadFailed(Int)
        case uploadError(String)

        var errorDescription: String? {
            switch self {
            case let .unknownError(statusCode):
                return
                    "The build archive could not be uploaded due to an unknown server response of \(statusCode)."
            case let .forbidden(message), let .notFound(message), let .unauthorized(message),
                 let .badRequest(message):
                return message
            case let .uploadFailed(statusCode):
                return "The build archive upload to storage failed with status \(statusCode)."
            case let .uploadError(message):
                return "The build archive upload to storage failed: \(message)."
            }
        }
    }

    public struct ServerUpload {
        public let id: String
        public let uploadURL: URL
    }

    public struct UploadBuildArchiveService: UploadBuildArchiveServicing {
        private let fullHandleService: FullHandleServicing

        public init(
            fullHandleService: FullHandleServicing = FullHandleService()
        ) {
            self.fullHandleService = fullHandleService
        }

        public func uploadBuildArchive(
            id: String,
            fullHandle: String,
            serverURL: URL,
            archivePath: AbsolutePath,
            contentLength: Int
        ) async throws -> ServerUpload {
            let client = Client.authenticated(serverURL: serverURL)
            let handles = try fullHandleService.parse(fullHandle)

            let response = try await client.createUpload(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                body: .json(
                    .init(
                        content_length: contentLength,
                        id: id,
                        purpose: .build_archive
                    )
                )
            )

            let upload: ServerUpload
            switch response {
            case let .ok(okResponse):
                switch okResponse.body {
                case let .json(uploadResponse):
                    guard let uploadURL = URL(string: uploadResponse.upload_url) else {
                        throw UploadBuildArchiveServiceError.badRequest("Invalid upload URL returned by server.")
                    }
                    upload = ServerUpload(id: uploadResponse.id, uploadURL: uploadURL)
                }
            case let .forbidden(forbiddenResponse):
                switch forbiddenResponse.body {
                case let .json(error):
                    throw UploadBuildArchiveServiceError.forbidden(error.message)
                }
            case let .unauthorized(unauthorizedResponse):
                switch unauthorizedResponse.body {
                case let .json(error):
                    throw UploadBuildArchiveServiceError.unauthorized(error.message)
                }
            case let .notFound(notFoundResponse):
                switch notFoundResponse.body {
                case let .json(error):
                    throw UploadBuildArchiveServiceError.notFound(error.message)
                }
            case let .badRequest(badRequestResponse):
                switch badRequestResponse.body {
                case let .json(error):
                    throw UploadBuildArchiveServiceError.badRequest(error.message)
                }
            case let .undocumented(statusCode: statusCode, _):
                throw UploadBuildArchiveServiceError.unknownError(statusCode)
            }

            var request = URLRequest(url: upload.uploadURL)
            request.httpMethod = "PUT"
            request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
            request.setValue("\(contentLength)", forHTTPHeaderField: "Content-Length")

            let fileURL = URL(fileURLWithPath: archivePath.pathString)
            let (_, uploadResponse) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
            guard let httpResponse = uploadResponse as? HTTPURLResponse else {
                throw UploadBuildArchiveServiceError.uploadError("No HTTP response received")
            }
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                throw UploadBuildArchiveServiceError.uploadFailed(httpResponse.statusCode)
            }

            return upload
        }
    }
#endif
