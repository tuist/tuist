import Foundation
import Path
import TuistAlert
import TuistConfigLoader
import TuistEnvironment
import TuistLogging
import TuistServer

protocol ProjectTokensCreateServicing {
    func run(
        fullHandle: String,
        directory: String?
    ) async throws
}

final class ProjectTokensCreateService: ProjectTokensCreateServicing {
    private let createProjectTokenService: CreateProjectTokenServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    convenience init() {
        self.init(
            createProjectTokenService: CreateProjectTokenService(),
            serverEnvironmentService: ServerEnvironmentService(),
            configLoader: ConfigLoader()
        )
    }

    init(
        createProjectTokenService: CreateProjectTokenServicing,
        serverEnvironmentService: ServerEnvironmentServicing,
        configLoader: ConfigLoading
    ) {
        self.createProjectTokenService = createProjectTokenService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
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

        let token = try await createProjectTokenService.createProjectToken(
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        Logger.current.info(.init(stringLiteral: token))
    }
}
