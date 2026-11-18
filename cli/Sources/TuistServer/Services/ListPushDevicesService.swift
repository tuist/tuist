import Foundation
import Mockable
import OpenAPIRuntime

@Mockable
public protocol ListPushDevicesServicing: Sendable {
    func listPushDevices(
        serverURL: URL
    ) async throws -> [ServerPushDevice]
}

public enum ListPushDevicesServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    /// The server predates push notifications.
    case unsupported

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The devices could not be listed due to an unknown Tuist response of \(statusCode)."
        case .unsupported:
            return "This Tuist server doesn't support push notifications yet. Ask its administrator to update it."
        case let .unauthorized(message), let .forbidden(message):
            return message
        }
    }
}

public struct ListPushDevicesService: ListPushDevicesServicing {
    private let makeClient: @Sendable (URL) -> Client

    public init() {
        self.init(makeClient: { Client.authenticated(serverURL: $0) })
    }

    init(makeClient: @escaping @Sendable (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func listPushDevices(
        serverURL: URL
    ) async throws -> [ServerPushDevice] {
        let client = makeClient(serverURL)

        let response = try await client.listPushDevices(.init())
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return json.devices.map(ServerPushDevice.init)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw ListPushDevicesServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw ListPushDevicesServiceError.forbidden(error.message)
            }
        case .undocumented(statusCode: 404, _):
            throw ListPushDevicesServiceError.unsupported
        case let .undocumented(statusCode: statusCode, _):
            throw ListPushDevicesServiceError.unknownError(statusCode)
        }
    }
}
