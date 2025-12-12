import Foundation
import Path
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
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        revokeProjectTokenService: RevokeProjectTokenServicing = RevokeProjectTokenService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.revokeProjectTokenService = revokeProjectTokenService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        projectTokenId: String,
        fullHandle: String,
        directory: String?
    ) async throws {
        AlertController.current.warning(.alert(
            "Project tokens are deprecated in favor of account tokens",
            takeaway: "Learn more: https://docs.tuist.dev/en/guides/server/authentication#account-tokens"
        ))

        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(validating: directory, relativeTo: FileHandler.shared.currentPath)
        } else {
            directoryPath = FileHandler.shared.currentPath
        }
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        try await revokeProjectTokenService.revokeProjectToken(
            projectTokenId: projectTokenId,
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        Logger.current.info("The project token \(projectTokenId) was successfully revoked.")
    }
}
