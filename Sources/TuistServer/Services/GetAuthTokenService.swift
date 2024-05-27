import Foundation
import Mockable
import OpenAPIURLSession
import TuistSupport

@Mockable
public protocol GetAuthTokenServicing {
    func getAuthToken(
        serverURL: URL,
        deviceCode: String
    ) async throws -> String?
}

public enum GetAuthTokenServiceError: FatalError, Equatable {
    case unknownError(Int)
    case badRequest(String)

    public var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .badRequest:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The CLI authentication failed due to an unknown Tuist Cloud response of \(statusCode)."
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
    ) async throws -> String? {
        let client = Client.unauthenticatedCloud(serverURL: serverURL)

        let response = try await client.getDeviceCode(
            .init(path: .init(device_code: deviceCode))
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(token):
                return token.token
            }
        case .accepted:
            return nil
        case let .badRequest(notFoundResponse):
            switch notFoundResponse.body {
            case let .json(error):
                throw GetAuthTokenServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CacheExistsServiceError.unknownError(statusCode)
        }
    }
}
