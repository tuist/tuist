import Foundation
import Mockable
import OpenAPIRuntime

@Mockable
public protocol RemovePushDeviceServicing: Sendable {
    func removePushDevice(
        registrationID: String,
        serverURL: URL
    ) async throws
}

enum RemovePushDeviceServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The device could not be removed due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message), let .forbidden(message):
            return message
        }
    }
}

public struct RemovePushDeviceService: RemovePushDeviceServicing {
    public init() {}

    public func removePushDevice(
        registrationID: String,
        serverURL: URL
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.removePushDevice(
            .init(path: .init(registration_id: registrationID))
        )
        switch response {
        case .noContent:
            break
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw RemovePushDeviceServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw RemovePushDeviceServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw RemovePushDeviceServiceError.unknownError(statusCode)
        }
    }
}
