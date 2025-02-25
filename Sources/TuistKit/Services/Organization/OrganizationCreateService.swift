import Foundation
import Path
import ServiceContextModule
import TuistLoader
import TuistServer
import TuistSupport

protocol OrganizationCreateServicing {
    func run(
        organizationName: String,
        directory: String?
    ) async throws
}

final class OrganizationCreateService: OrganizationCreateServicing {
    private let createOrganizationService: CreateOrganizationServicing
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    init(
        createOrganizationService: CreateOrganizationServicing = CreateOrganizationService(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.createOrganizationService = createOrganizationService
        self.serverURLService = serverURLService
        self.configLoader = configLoader
    }

    func run(
        organizationName: String,
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

        let organization = try await createOrganizationService.createOrganization(
            name: organizationName,
            serverURL: serverURL
        )

        ServiceContext.current?.logger?.info("Tuist organization \(organization.name) was successfully created 🎉")
    }
}
