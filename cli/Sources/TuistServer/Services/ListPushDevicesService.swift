import Foundation
import Mockable
import OpenAPIRuntime

@Mockable
public protocol ListPushDevicesServicing: Sendable {
    func listPushDevices(
        serverURL: URL
    ) async throws -> [ServerPushDevice]
}

enum ListPushDevicesServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The devices could not be listed due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message), let .forbidden(message):
            return message
        }
    }
}

public struct ListPushDevicesService: ListPushDevicesServicing {
    public init() {}

    public func listPushDevices(
        serverURL: URL
    ) async throws -> [ServerPushDevice] {
        let client = Client.authenticated(serverURL: serverURL)

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
        case let .undocumented(statusCode: statusCode, _):
            throw ListPushDevicesServiceError.unknownError(statusCode)
        }
    }
}
