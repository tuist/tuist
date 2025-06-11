import Foundation
import Mockable
import OpenAPIURLSession

@Mockable
public protocol GetAuthTokenServicing {
    func getAuthToken(
        serverURL: URL,
        deviceCode: String
    ) async throws -> ServerAuthenticationTokens?
}

public enum GetAuthTokenServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case badRequest(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The CLI authentication failed due to an unknown Tuist response of \(statusCode)."
        case let .badRequest(message):
            return message
        }
    }
}

public final class GetAuthTokenService: GetAuthTokenServicing {
    public init() {}

    public func getAuthToken(
        serverURL: URL,
        deviceCode: String
    ) async throws -> ServerAuthenticationTokens? {
        let client = Client.unauthenticated(serverURL: serverURL)

        let response = try await client.getDeviceCode(
            .init(path: .init(device_code: deviceCode))
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(token):
                guard let refreshToken = token.refresh_token,
                      let accessToken = token.access_token
                else { return nil }
                return ServerAuthenticationTokens(
                    accessToken: accessToken,
                    refreshToken: refreshToken
                )
            }
        case .accepted:
            return nil
        case let .badRequest(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw GetAuthTokenServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetAuthTokenServiceError.unknownError(statusCode)
        }
    }
}
