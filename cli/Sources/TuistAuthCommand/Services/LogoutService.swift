import Foundation
import Logging
import Path
import TuistConfigLoader
import TuistConstants
import TuistEnvironment
import TuistLogging
import TuistServer

public protocol LogoutServicing: AnyObject {
    func logout(
        directory: String?,
        serverURL: String?
    ) async throws
}

public final class LogoutService: LogoutServicing {
    private let serverSessionController: ServerSessionControlling
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    public init(
        serverSessionController: ServerSessionControlling = ServerSessionController(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.serverSessionController = serverSessionController
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    public func logout(
        directory: String?,
        serverURL: String?
    ) async throws {
        let resolvedServerURL: URL

        if let serverURL {
            guard let url = URL(string: serverURL) else {
                throw LogoutServiceError.invalidServerURL(serverURL)
            }
            resolvedServerURL = try serverEnvironmentService.url(configServerURL: url)
        } else {
            let directoryPath: AbsolutePath
            if let directory {
                let cwd = try await Environment.current.currentWorkingDirectory()
                directoryPath = try AbsolutePath(validating: directory, relativeTo: cwd)
            } else {
                directoryPath = try await Environment.current.currentWorkingDirectory()
            }
            let config = try await configLoader.loadConfig(path: directoryPath)
            resolvedServerURL = try serverEnvironmentService.url(configServerURL: config.url)
        }

        try await serverSessionController.logout(serverURL: resolvedServerURL)
        Logger.current.notice("Successfully logged out")
    }
}

enum LogoutServiceError: LocalizedError, Equatable {
    case invalidServerURL(String)

    var errorDescription: String? {
        switch self {
        case let .invalidServerURL(url):
            return "Invalid server URL: \(url)"
        }
    }
}
