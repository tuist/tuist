import Foundation
import OpenAPIURLSession
import TuistHTTP

public protocol DeletePreviewServicing: Sendable {
    func deletePreview(
        _ previewId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws
}

enum DeletePreviewServiceError: LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)
    case badRequest(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The preview could not be deleted due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .unauthorized(message), let .notFound(message), let .badRequest(message):
            return message
        }
    }
}

public final class DeletePreviewService: DeletePreviewServicing {
    private let fullHandleService: FullHandleServicing

    public init(
        fullHandleService: FullHandleServicing = FullHandleService()
    ) {
        self.fullHandleService = fullHandleService
    }

    public func deletePreview(
        _ previewId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws {
        let handles = try fullHandleService.parse(fullHandle)
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.deletePreview(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    preview_id: previewId
                )
            )
        )
        switch response {
        case .noContent:
            // noop
            break
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw DeletePreviewServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw DeletePreviewServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DeletePreviewServiceError.unauthorized(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw DeletePreviewServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw DeletePreviewServiceError.unknownError(statusCode)
        }
    }
}
