import Foundation
import Noora
import TuistConfigLoader
import TuistEnvironment
import TuistServer

public protocol BazelCredentialHelperCommandServicing {
    func run(
        helperCommand: String,
        directory: String?
    ) async throws
}

public struct BazelCredentialHelperCommandService: BazelCredentialHelperCommandServicing {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let configLoader: ConfigLoading

    public init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.serverAuthenticationController = serverAuthenticationController
        self.configLoader = configLoader
    }

    public func run(
        helperCommand: String,
        directory: String?
    ) async throws {
        let response = try await credentials(helperCommand: helperCommand, directory: directory)
        try Noora.current.json(response)
    }

    func credentials(
        helperCommand: String,
        directory: String?
    ) async throws -> BazelCredentialHelperResponse {
        guard helperCommand == "get" else {
            throw BazelCredentialHelperCommandServiceError.unsupportedCommand(helperCommand)
        }

        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        guard let token = try await serverAuthenticationController.authenticationToken(serverURL: serverURL)
        else {
            throw BazelCredentialHelperCommandServiceError.notAuthenticated
        }

        let expiryDate: Date? = switch token {
        case let .user(accessToken: accessToken, refreshToken: _):
            accessToken.expiryDate
        case let .account(accessToken):
            accessToken.expiryDate
        case .project:
            nil
        }

        return BazelCredentialHelperResponse(
            headers: ["Authorization": ["Bearer \(token.value)"]],
            expires: expiryDate.map { ISO8601DateFormatter().string(from: $0) }
        )
    }
}

struct BazelCredentialHelperResponse: Codable, Equatable {
    let headers: [String: [String]]
    let expires: String?
}

public enum BazelCredentialHelperCommandServiceError: LocalizedError, Equatable {
    case unsupportedCommand(String)
    case notAuthenticated

    public var errorDescription: String? {
        switch self {
        case let .unsupportedCommand(command):
            return "The credential helper command '\(command)' is not supported. Only 'get' is supported."
        case .notAuthenticated:
            return
                "You are not authenticated. Refer to the documentation for authentication options: https://tuist.dev/en/docs/guides/server/authentication"
        }
    }
}
