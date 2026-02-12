import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistLogging
import TuistServer

protocol ProjectCreateServicing {
    func run(
        fullHandle: String,
        directory: String?,
        buildSystem: Components.Schemas.Project.build_systemPayload?
    ) async throws
}

final class ProjectCreateService: ProjectCreateServicing {
    private let createProjectService: CreateProjectServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        createProjectService: CreateProjectServicing = CreateProjectService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.createProjectService = createProjectService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String,
        directory: String?,
        buildSystem: Components.Schemas.Project.build_systemPayload?
    ) async throws {
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
        let config = try await configLoader.loadConfig(path: directoryPath)

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let resolvedBuildSystem: Components.Schemas.Project.build_systemPayload = buildSystem ?? Noora.current.singleChoicePrompt(
            title: "Build system",
            question: "Which build system does your project use?",
            collapseOnSelection: true
        )

        let project = try await createProjectService.createProject(
            fullHandle: fullHandle,
            buildSystem: resolvedBuildSystem,
            serverURL: serverURL
        )

        Logger.current.info("Tuist project \(project.fullName) was successfully created 🎉")
    }
}
