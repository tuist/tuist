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

enum RemovePushDeviceServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case tooManyRequests(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The device could not be removed due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message), let .forbidden(message), let .tooManyRequests(message):
            return message
        }
    }
}

public struct RemovePushDeviceService: RemovePushDeviceServicing {
    private let makeClient: @Sendable (URL) -> Client

    public init() {
        self.init(makeClient: { Client.authenticated(serverURL: $0) })
    }

    init(makeClient: @escaping @Sendable (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func removePushDevice(
        registrationID: String,
        serverURL: URL
    ) async throws {
        let client = makeClient(serverURL)

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
        case let .tooManyRequests(tooManyRequests):
            switch tooManyRequests.body {
            case let .json(error):
                throw RemovePushDeviceServiceError.tooManyRequests(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw RemovePushDeviceServiceError.unknownError(statusCode)
        }
    }
}
