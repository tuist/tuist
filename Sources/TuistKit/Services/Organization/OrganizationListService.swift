import Foundation
import Path
import ServiceContextModule
import TuistLoader
import TuistServer
import TuistSupport

protocol OrganizationListServicing {
    func run(
        json: Bool,
        directory: String?
    ) async throws
}

final class OrganizationListService: OrganizationListServicing {
    private let listOrganizationsService: ListOrganizationsServicing
    private let serverURLService: ServerURLServicing
    private let configLoader: ConfigLoading

    init(
        listOrganizationsService: ListOrganizationsServicing = ListOrganizationsService(),
        serverURLService: ServerURLServicing = ServerURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listOrganizationsService = listOrganizationsService
        self.serverURLService = serverURLService
        self.configLoader = configLoader
    }

    func run(
        json: Bool,
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

        let organizations = try await listOrganizationsService.listOrganizations(
            serverURL: serverURL
        )

        if json {
            let json = organizations.toJSON()
            ServiceContext.current?.logger?.info(.init(stringLiteral: json.toString(prettyPrint: true)), metadata: .json)
            return
        }

        if organizations.isEmpty {
            ServiceContext.current?.logger?
                .info("You currently have no Cloud organizations. Create one by running `tuist organization create`.")
            return
        }

        let organizationsString = "Listing all your organizations:\n" + organizations.map { "  • \($0)" }
            .joined(separator: "\n")
        ServiceContext.current?.logger?.info("\(organizationsString)")
    }
}
