import Foundation
import Mockable
import OpenAPIURLSession
import OpenAPIRuntime

@Mockable
public protocol UploadCASArtifactServicing: Sendable {
    func uploadCASArtifact(
        _ data: Data,
        casId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws
}

public enum UploadCASArtifactServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case uploadFailed

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The CAS artifact could not be uploaded due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message), let .forbidden(message), let .notFound(message):
            return message
        case .uploadFailed:
            return "The CAS artifact upload failed due to an unknown error."
        }
    }
}

public final class UploadCASArtifactService: UploadCASArtifactServicing {
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

    public func uploadCASArtifact(
        _ data: Data,
        casId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try! await client.uploadCASArtifact(
            .init(
                path: .init(id: casId),
                query: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                body: .binary(HTTPBody(data))
            )
        )
        switch response {
        case .ok:
            return
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw UploadCASArtifactServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw UploadCASArtifactServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _payload):
            throw UploadCASArtifactServiceError.unknownError(statusCode)
        }
    }
}
