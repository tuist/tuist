import Foundation
import Mockable
import TuistHTTP

@Mockable
public protocol GetPreviewServicing: Sendable {
    func getPreview(
        _ previewId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws -> ServerPreview
}

public enum GetPreviewServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)
    case invalidPreview(String)
    case badRequest(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The preview could not be downloaded due to an unknown Tuist server response of \(statusCode)."
        case let .notFound(message), let .forbidden(message), let .unauthorized(message), let .badRequest(message):
            return message
        case let .invalidPreview(id):
            return "The preview \(id) is invalid."
        }
    }
}

public final class GetPreviewService: GetPreviewServicing {
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

    public func getPreview(
        _ previewId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws -> ServerPreview {
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
            case let .json(preview):
                guard let preview = ServerPreview(preview) else {
                    throw GetPreviewServiceError.invalidPreview(previewId)
                }
                return preview
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetPreviewServiceError.unknownError(statusCode)
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw GetPreviewServiceError.forbidden(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw GetPreviewServiceError.notFound(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw GetPreviewServiceError.unauthorized(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw GetPreviewServiceError.badRequest(error.message)
            }
        }
    }
}
