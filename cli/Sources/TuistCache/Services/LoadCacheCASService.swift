import Foundation
import Mockable
import OpenAPIRuntime
import OpenAPIURLSession
import TuistHTTP
import TuistServer

@Mockable
public protocol LoadCacheCASServicing: Sendable {
    func loadCacheCAS(
        casId: String,
        fullHandle: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws -> Data
}

public enum LoadCacheCASServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case freeTierExhausted(String)
    case badRequest(String)
    case unprocessableContent(String)
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The CAS artifact could not be loaded due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message),
             let .forbidden(message),
             let .freeTierExhausted(message),
             let .notFound(message),
             let .badRequest(message),
             let .unprocessableContent(message):
            return message
        }
    }
}

public struct LoadCacheCASService: LoadCacheCASServicing {
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

    public func loadCacheCAS(
        casId: String,
        fullHandle: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws -> Data {
        let client = Client.authenticated(
            cacheURL: serverURL,
            authenticationURL: authenticationURL,
            serverAuthenticationController: serverAuthenticationController,
            session: .tuistCAS,
            retriesTransportErrors: false,
            fullHandle: fullHandle
        )
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.downloadXcodeArtifact(
            .init(
                path: .init(id: casId),
                query: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                )
            )
        )

        switch response {
        case let .ok(success):
            switch success.body {
            case let .binary(httpBody):
                let data = try await Data(collecting: httpBody, upTo: .max)
                return data
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw LoadCacheCASServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw LoadCacheCASServiceError.forbidden(error.message)
            }
        case let .code402(paymentRequired):
            switch paymentRequired.body {
            case let .json(error):
                throw LoadCacheCASServiceError.freeTierExhausted(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw LoadCacheCASServiceError.notFound(error.message)
            }
        case let .unprocessableContent(unprocessableContent):
            switch unprocessableContent.body {
            case let .json(error):
                throw LoadCacheCASServiceError.unprocessableContent(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw LoadCacheCASServiceError.unknownError(statusCode)
        }
    }
}
