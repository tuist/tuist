import Foundation
import Mockable
import OpenAPIRuntime

public struct ServerDeviceAuthorization: Equatable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURL: URL
    public let expiresIn: Int
    public let interval: Int
}

@Mockable
public protocol CreateDeviceCodeServicing {
    /// Starts the device authorization flow (RFC 8628).
    /// - Returns: The device authorization, or nil when the server predates the flow and doesn't have the endpoint.
    func createDeviceCode(serverURL: URL) async throws -> ServerDeviceAuthorization?
}

enum CreateDeviceCodeServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case invalidVerificationURL(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            "Starting the sign-in failed due to an unknown Tuist response of \(statusCode)."
        case let .invalidVerificationURL(url):
            "The server returned an invalid sign-in URL: \(url)"
        }
    }
}

public struct CreateDeviceCodeService: CreateDeviceCodeServicing {
    private let makeClient: (URL) -> Client

    public init() {
        makeClient = { Client.unauthenticated(serverURL: $0) }
    }

    init(makeClient: @escaping (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func createDeviceCode(serverURL: URL) async throws -> ServerDeviceAuthorization? {
        let response = try await makeClient(serverURL).createDeviceCode()

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(authorization):
                guard let verificationURL = URL(string: authorization.verification_uri) else {
                    throw CreateDeviceCodeServiceError.invalidVerificationURL(authorization.verification_uri)
                }
                return ServerDeviceAuthorization(
                    deviceCode: authorization.device_code,
                    userCode: authorization.user_code,
                    verificationURL: verificationURL,
                    expiresIn: authorization.expires_in,
                    interval: authorization.interval
                )
            }
        // Servers released before the device authorization flow have no route for it.
        case .undocumented(statusCode: 404, _), .undocumented(statusCode: 405, _):
            return nil
        case let .undocumented(statusCode: statusCode, _):
            throw CreateDeviceCodeServiceError.unknownError(statusCode)
        }
    }
}
