import Foundation
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistServer

protocol RunnerSSHCommandServicing {
    func run(jobRef: String, path: String?) async throws
}

struct RunnerSSHCommandService: RunnerSSHCommandServicing {
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let shellSessionService: RunnerShellSessionServicing
    private let terminalClient: RunnerShellTerminalClienting

    init(
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        shellSessionService: RunnerShellSessionServicing = RunnerShellSessionService(),
        terminalClient: RunnerShellTerminalClienting = RunnerShellTerminalClient()
    ) {
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.serverAuthenticationController = serverAuthenticationController
        self.shellSessionService = shellSessionService
        self.terminalClient = terminalClient
    }

    func run(jobRef: String, path: String?) async throws {
        let directory = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: directory)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        guard let token = try await serverAuthenticationController.authenticationToken(serverURL: serverURL) else {
            throw ServerSessionControllerError.unauthenticated
        }

        let session = try await shellSessionService.create(
            jobRef: jobRef,
            serverURL: serverURL,
            token: token.value
        )

        try await terminalClient.attach(to: session)
    }
}
