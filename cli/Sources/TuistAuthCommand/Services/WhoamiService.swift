import Foundation
import Logging
import Path
import TuistConfigLoader
import TuistConstants
import TuistEnvironment
import TuistLogging
import TuistServer

public protocol WhoamiServicing {
    func run(
        directory: String?,
        serverURL: String?
    ) async throws
}

public struct WhoamiService: WhoamiServicing {
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    public init(
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.serverAuthenticationController = serverAuthenticationController
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    public init(
        serverSessionController _: ServerSessionControlling,
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.init(
            serverAuthenticationController: serverAuthenticationController,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )
    }

    public func run(
        directory: String?,
        serverURL: String?
    ) async throws {
        let resolvedServerURL: URL

        if let serverURL {
            guard let url = URL(string: serverURL) else {
                throw WhoamiServiceError.invalidServerURL(serverURL)
            }
            resolvedServerURL = try serverEnvironmentService.url(configServerURL: url)
        } else {
            let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
            let config = try await configLoader.loadConfig(path: directoryPath)
            resolvedServerURL = try serverEnvironmentService.url(configServerURL: config.url)
        }

        guard let token = try await serverAuthenticationController.authenticationToken(
            serverURL: resolvedServerURL
        ) else {
            throw ServerSessionControllerError.unauthenticated
        }

        switch token {
        case let .user(accessToken: accessToken, refreshToken: _):
            if let username = accessToken.preferredUsername {
                Logger.current.notice("\(username)")
            } else if let email = accessToken.email {
                Logger.current.notice("\(email)")
            } else {
                Logger.current.notice("Authenticated as user")
            }
        case let .account(accessToken):
            if let username = accessToken.preferredUsername {
                Logger.current.notice("\(username) (account token)")
            } else if let email = accessToken.email {
                Logger.current.notice("\(email) (account token)")
            } else {
                Logger.current.notice("Authenticated with an account token")
            }
        case .project:
            if Environment.current.tuistVariables[Constants.EnvironmentVariables.token] != nil {
                Logger.current.notice("Authenticated with a project token (TUIST_TOKEN)")
            } else if Environment.current.tuistVariables[Constants.EnvironmentVariables.deprecatedToken] != nil {
                Logger.current.notice("Authenticated with a project token (TUIST_CONFIG_TOKEN)")
            } else if Environment.current.tuistVariables["TUIST_CONFIG_CLOUD_TOKEN"] != nil {
                Logger.current.notice("Authenticated with a project token (TUIST_CONFIG_CLOUD_TOKEN)")
            } else {
                Logger.current.notice("Authenticated with a project token")
            }
        }
    }
}

enum WhoamiServiceError: LocalizedError, Equatable {
    case invalidServerURL(String)

    var errorDescription: String? {
        switch self {
        case let .invalidServerURL(url):
            return "Invalid server URL: \(url)"
        }
    }
}
