import Foundation
import Mockable
import OpenAPIRuntime

public enum PushDeviceEnvironment: String, Sendable {
    case sandbox
    case production
}

@Mockable
public protocol RegisterPushDeviceServicing: Sendable {
    /// Registers the app installation for push notifications and returns the server registration ID.
    func registerPushDevice(
        installationID: String,
        token: String,
        environment: PushDeviceEnvironment,
        name: String?,
        serverURL: URL
    ) async throws -> String
}

public enum RegisterPushDeviceServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case badRequest(String)
    case unauthorized(String)
    case forbidden(String)
    case tooManyRequests(String)
    /// The installation belongs to another user.
    case conflict(String)
    /// The installation ID can no longer be registered, so a new one is needed.
    case retired(String)
    /// The user removed this device from their device list, or the server gave a reason this app doesn't know.
    case removed(String)
    /// The server predates push notifications, so the app should stop registering quietly.
    case unsupported

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The device could not be registered for notifications due to an unknown Tuist response of \(statusCode)."
        case .unsupported:
            return "This Tuist server doesn't support push notifications yet. Ask its administrator to update it."
        case let .badRequest(message), let .unauthorized(message), let .forbidden(message), let .conflict(message),
             let .retired(message), let .removed(message), let .tooManyRequests(message):
            return message
        }
    }
}

public struct RegisterPushDeviceService: RegisterPushDeviceServicing {
    private let makeClient: @Sendable (URL) -> Client

    public init() {
        self.init(makeClient: { Client.authenticated(serverURL: $0) })
    }

    init(makeClient: @escaping @Sendable (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func registerPushDevice(
        installationID: String,
        token: String,
        environment: PushDeviceEnvironment,
        name: String?,
        serverURL: URL
    ) async throws -> String {
        let client = makeClient(serverURL)

        let response = try await client.registerPushDevice(
            .init(
                path: .init(installation_id: installationID),
                body: .json(
                    .init(
                        environment: environment == .sandbox ? .sandbox : .production,
                        name: name,
                        platform: .ios,
                        token: token
                    )
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return json.registration_id
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw RegisterPushDeviceServiceError.badRequest(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw RegisterPushDeviceServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw RegisterPushDeviceServiceError.forbidden(error.message)
            }
        case let .conflict(conflict):
            switch conflict.body {
            case let .json(error):
                throw RegisterPushDeviceServiceError.conflict(error.message)
            }
        case let .gone(gone):
            let error = try gone.body.json
            // Unknown reasons keep notifications off rather than re-registering under a new ID.
            throw error.reason == "retired"
                ? RegisterPushDeviceServiceError.retired(error.message)
                : RegisterPushDeviceServiceError.removed(error.message)
        case let .tooManyRequests(tooManyRequests):
            switch tooManyRequests.body {
            case let .json(error):
                throw RegisterPushDeviceServiceError.tooManyRequests(error.message)
            }
        case .undocumented(statusCode: 404, _):
            throw RegisterPushDeviceServiceError.unsupported
        case let .undocumented(statusCode: statusCode, _):
            throw RegisterPushDeviceServiceError.unknownError(statusCode)
        }
    }
}
