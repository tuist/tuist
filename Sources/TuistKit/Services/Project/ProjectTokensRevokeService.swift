import Foundation
import Path
import ServiceContextModule
import TuistLoader
import TuistServer
import TuistSupport

protocol ProjectTokensRevokeServicing {
    func run(
        projectTokenId: String,
        fullHandle: String,
        directory: String?
    ) async throws
}

final class ProjectTokensRevokeService: ProjectTokensRevokeServicing {
    private let revokeProjectTokenService: RevokeProjectTokenServicing
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    init(
        revokeProjectTokenService: RevokeProjectTokenServicing = RevokeProjectTokenService(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.revokeProjectTokenService = revokeProjectTokenService
        self.serverURLService = serverURLService
        self.configLoader = configLoader
    }

    func run(
        projectTokenId: String,
        fullHandle: String,
        directory: String?
    ) async throws {
        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(validating: directory, relativeTo: FileHandler.shared.currentPath)
        } else {
            directoryPath = FileHandler.shared.currentPath
        }
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverURLService.url(configServerURL: config.url)

        try await revokeProjectTokenService.revokeProjectToken(
            projectTokenId: projectTokenId,
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        ServiceContext.current?.logger?.info("The project token \(projectTokenId) was successfully revoked.")
    }
}
