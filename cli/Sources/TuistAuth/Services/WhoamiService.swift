import Foundation
import Logging
import Path
import TuistConstants
import TuistEnvironment
import TuistLogging
import TuistServer

#if os(macOS)
    import TuistLoader
    import TuistSupport
#endif

public protocol WhoamiServicing: AnyObject {
    func run(
        directory: String?,
        serverURL: String?
    ) async throws
}

public final class WhoamiService: WhoamiServicing {
    private let serverSessionController: ServerSessionControlling
    private let serverEnvironmentService: ServerEnvironmentServicing
    #if os(macOS)
        private let configLoader: ConfigLoading
    #endif

    public init(
        serverSessionController: ServerSessionControlling = ServerSessionController(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService()
    ) {
        self.serverSessionController = serverSessionController
        self.serverEnvironmentService = serverEnvironmentService
        #if os(macOS)
            self.configLoader = ConfigLoader()
        #endif
    }

    #if os(macOS)
        public init(
            serverSessionController: ServerSessionControlling = ServerSessionController(),
            serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
            configLoader: ConfigLoading = ConfigLoader()
        ) {
            self.serverSessionController = serverSessionController
            self.serverEnvironmentService = serverEnvironmentService
            self.configLoader = configLoader
        }
    #endif

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
            #if os(macOS)
                let directoryPath: AbsolutePath
                if let directory {
                    directoryPath = try AbsolutePath(
                        validating: directory, relativeTo: FileHandler.shared.currentPath
                    )
                } else {
                    directoryPath = FileHandler.shared.currentPath
                }
                let config = try await configLoader.loadConfig(path: directoryPath)
                resolvedServerURL = try serverEnvironmentService.url(configServerURL: config.url)
            #else
                if let envURL = Environment.current.tuistVariables["URL"],
                   let url = URL(string: envURL)
                {
                    resolvedServerURL = try serverEnvironmentService.url(configServerURL: url)
                } else {
                    resolvedServerURL = Constants.URLs.production
                }
            #endif
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
