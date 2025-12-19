import FileSystem
import Foundation
import Mockable
import OpenAPIURLSession
import Path
import TuistHTTP

@Mockable
public protocol UploadPreviewIconServicing {
    func uploadPreviewIcon(
        _ icon: AbsolutePath,
        preview: ServerPreview,
        serverURL: URL,
        fullHandle: String
    ) async throws
}

enum UploadPreviewIconServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case uploadFailed

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The preview icon could not be uploaded due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message), let .forbidden(message), let .notFound(message):
            return message
        case .uploadFailed:
            return "The preview icon failed due to an unknown error."
        }
    }
}

public final class UploadPreviewIconService: UploadPreviewIconServicing {
    private let fullHandleService: FullHandleServicing
    private let fileSystem: FileSysteming
    private let urlSession: URLSession

    public convenience init() {
        self.init(
            fullHandleService: FullHandleService(),
            fileSystem: FileSystem(),
            urlSession: .tuistShared
        )
    }

    init(
        fullHandleService: FullHandleServicing,
        fileSystem: FileSysteming,
        urlSession: URLSession
    ) {
        self.fullHandleService = fullHandleService
        self.fileSystem = fileSystem
        self.urlSession = urlSession
    }

    public func uploadPreviewIcon(
        _ icon: AbsolutePath,
        preview: ServerPreview,
        serverURL: URL,
        fullHandle: String
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)

        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.uploadPreviewIcon(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    preview_id: preview.id
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                let data = try await fileSystem.readFile(at: icon)
                let fileSize = try await fileSystem.fileSizeInBytes(at: icon)
                guard let url = URL(string: json.url) else { fatalError() }
                let (_, response) = try await urlSession.data(
                    for: uploadRequest(
                        url: url,
                        fileSize: fileSize,
                        data: data
                    )
                )

                guard let urlResponse = response as? HTTPURLResponse,
                      (200 ..< 300).contains(urlResponse.statusCode)
                else {
                    throw UploadPreviewIconServiceError.uploadFailed
                }
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw UploadPreviewIconServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw UploadPreviewIconServiceError.unknownError(statusCode)
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw UploadPreviewIconServiceError.unauthorized(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw UploadPreviewIconServiceError.notFound(error.message)
            }
        }
    }

    private func uploadRequest(url: URL, fileSize: Int64?, data: Data) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        if let fileSize {
            request.setValue(String(fileSize), forHTTPHeaderField: "Content-Length")
        }
        request.httpBody = data
        return request
    }
}
