import Foundation
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistLogging
import TuistServer

protocol OrganizationCreateServicing {
    func run(
        organizationName: String,
        directory: String?
    ) async throws
}

struct OrganizationCreateService: OrganizationCreateServicing {
    private let createOrganizationService: CreateOrganizationServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        createOrganizationService: CreateOrganizationServicing = CreateOrganizationService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.createOrganizationService = createOrganizationService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        organizationName: String,
        directory: String?
    ) async throws {
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let organization = try await createOrganizationService.createOrganization(
            name: organizationName,
            serverURL: serverURL
        )

        Logger.current.info("Tuist organization \(organization.name) was successfully created 🎉")
    }
}
