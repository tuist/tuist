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

        let whoami = try await serverSessionController.authenticatedHandle(serverURL: resolvedServerURL)
        Logger.current.notice("\(whoami)")
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
