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

enum UnregisterPushDeviceServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case badRequest(String)
    case unauthorized(String)
    case forbidden(String)
    case tooManyRequests(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The device could not be unregistered from notifications due to an unknown Tuist response of \(statusCode)."
        case let .badRequest(message), let .unauthorized(message), let .forbidden(message), let .tooManyRequests(message):
            return message
        }
    }
}

public struct UnregisterPushDeviceService: UnregisterPushDeviceServicing {
    private let makeClient: @Sendable (URL) -> Client

    public init() {
        self.init(makeClient: { Client.authenticated(serverURL: $0) })
    }

    init(makeClient: @escaping @Sendable (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func unregisterPushDevice(
        installationID: String,
        serverURL: URL
    ) async throws {
        let client = makeClient(serverURL)

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
        case let .tooManyRequests(tooManyRequests):
            switch tooManyRequests.body {
            case let .json(error):
                throw UnregisterPushDeviceServiceError.tooManyRequests(error.message)
            }
        case .undocumented(statusCode: 404, _):
            // A server that predates push notifications never registered this installation.
            break
        case let .undocumented(statusCode: statusCode, _):
            throw UnregisterPushDeviceServiceError.unknownError(statusCode)
        }
    }
}
