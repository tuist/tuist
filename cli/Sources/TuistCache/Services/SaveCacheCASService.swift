import Crypto
import Foundation
import Mockable
import OpenAPIRuntime
import OpenAPIURLSession
import TuistHTTP
import TuistServer

@Mockable
public protocol SaveCacheCASServicing: Sendable {
    func saveCacheCAS(
        _ data: Data,
        casId: String,
        fullHandle: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws
}

public enum SaveCacheCASServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case freeTierExhausted(String)
    case notFound(String)
    case badRequest(String)
    case unprocessableContent(String)
    case requestTimeout(String)
    case contentTooLarge(String)
    case internalServerError(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The CAS artifact could not be uploaded due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message),
             let .forbidden(message),
             let .freeTierExhausted(message),
             let .notFound(message),
             let .badRequest(message),
             let .unprocessableContent(message),
             let .requestTimeout(message),
             let .contentTooLarge(message),
             let .internalServerError(message):
            return message
        }
    }
}

public struct SaveCacheCASService: SaveCacheCASServicing {
    private let fullHandleService: FullHandleServicing

    public init() {
        self.init(
            fullHandleService: FullHandleService()
        )
    }

    init(
        fullHandleService: FullHandleServicing
    ) {
        self.fullHandleService = fullHandleService
    }

    public func saveCacheCAS(
        _ data: Data,
        casId: String,
        fullHandle: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws {
        let client = Client.authenticated(
            cacheURL: serverURL,
            authenticationURL: authenticationURL,
            serverAuthenticationController: serverAuthenticationController,
            session: .tuistCAS,
            fullHandle: fullHandle
        )
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.saveXcodeArtifact(
            .init(
                path: .init(id: casId),
                query: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                headers: .init(tuist_hyphen_checksum_hyphen_sha256: Self.checksumSHA256(of: data)),
                body: .binary(HTTPBody(data))
            )
        )
        switch response {
        case .noContent:
            return
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw SaveCacheCASServiceError.badRequest(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw SaveCacheCASServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw SaveCacheCASServiceError.forbidden(error.message)
            }
        case let .code402(paymentRequired):
            switch paymentRequired.body {
            case let .json(error):
                throw SaveCacheCASServiceError.freeTierExhausted(error.message)
            }
        case let .requestTimeout(timeout):
            switch timeout.body {
            case let .json(error):
                throw SaveCacheCASServiceError.requestTimeout(error.message)
            }
        case let .contentTooLarge(tooLarge):
            switch tooLarge.body {
            case let .json(error):
                throw SaveCacheCASServiceError.contentTooLarge(error.message)
            }
        case let .internalServerError(serverError):
            switch serverError.body {
            case let .json(error):
                throw SaveCacheCASServiceError.internalServerError(error.message)
            }
        case let .unprocessableContent(unprocessableContent):
            switch unprocessableContent.body {
            case let .json(error):
                throw SaveCacheCASServiceError.unprocessableContent(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw SaveCacheCASServiceError.unknownError(statusCode)
        }
    }

    /// The digest of exactly the bytes sent, so the server can refuse a body
    /// damaged after it was hashed. The CAS id is a hash of the uncompressed
    /// content and cannot stand in for it.
    static func checksumSHA256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
