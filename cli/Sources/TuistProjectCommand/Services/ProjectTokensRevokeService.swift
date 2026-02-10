import Foundation
import Path
import TuistAlert
import TuistConfigLoader
import TuistEnvironment
import TuistLogging
import TuistServer

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

        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
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
