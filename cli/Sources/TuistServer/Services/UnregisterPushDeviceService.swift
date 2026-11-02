import Foundation
import Mockable
import OpenAPIRuntime

@Mockable
public protocol UnregisterPushDeviceServicing: Sendable {
    func unregisterPushDevice(
        installationID: String,
        serverURL: URL
    ) async throws
}

enum UnregisterPushDeviceServiceError: LocalizedError {
    case unknownError(Int)
    case badRequest(String)
    case unauthorized(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The device could not be unregistered from notifications due to an unknown Tuist response of \(statusCode)."
        case let .badRequest(message), let .unauthorized(message), let .forbidden(message):
            return message
        }
    }
}

public struct UnregisterPushDeviceService: UnregisterPushDeviceServicing {
    public init() {}

    public func unregisterPushDevice(
        installationID: String,
        serverURL: URL
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.unregisterPushDevice(
            .init(path: .init(installation_id: installationID))
        )
        switch response {
        case .noContent:
            break
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw UnregisterPushDeviceServiceError.badRequest(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw UnregisterPushDeviceServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw UnregisterPushDeviceServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw UnregisterPushDeviceServiceError.unknownError(statusCode)
        }
    }
}
