import Foundation
import Mockable
import TuistHTTP

@Mockable
public protocol GenerateShardXctestrunUploadURLServicing {
    func generateURL(
        fullHandle: String,
        serverURL: URL,
        sessionId: String
    ) async throws -> String
}

public enum GenerateShardXctestrunUploadURLServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to generate xctestrun upload URL due to an unknown server response of \(statusCode)."
        case let .notFound(message), let .forbidden(message), let .unauthorized(message):
            return message
        }
    }
}

public struct GenerateShardXctestrunUploadURLService: GenerateShardXctestrunUploadURLServicing {
    private let fullHandleService: FullHandleServicing

    public init(
        fullHandleService: FullHandleServicing = FullHandleService()
    ) {
        self.fullHandleService = fullHandleService
    }

    public func generateURL(
        fullHandle: String,
        serverURL: URL,
        sessionId: String
    ) async throws -> String {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.generateShardXctestrunUploadURL(
            path: .init(
                account_handle: handles.accountHandle,
                project_handle: handles.projectHandle
            ),
            body: .json(
                .init(session_id: sessionId)
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(result):
                guard let url = result.data?.url else {
                    throw GenerateShardXctestrunUploadURLServiceError.unknownError(200)
                }
                return url
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw GenerateShardXctestrunUploadURLServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw GenerateShardXctestrunUploadURLServiceError.unauthorized(error.message)
            }
        case let .notFound(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw GenerateShardXctestrunUploadURLServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode, _):
            throw GenerateShardXctestrunUploadURLServiceError.unknownError(statusCode)
        }
    }
}
