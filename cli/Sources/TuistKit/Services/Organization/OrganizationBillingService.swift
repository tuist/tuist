import Foundation
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol OrganizationBillingServicing {
    func run(
        organizationName: String,
        directory: String?
    ) async throws
}

final class OrganizationBillingService: OrganizationBillingServicing {
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let opener: Opening
    private let configLoader: ConfigLoading

    init(
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        opener: Opening = Opener(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.serverEnvironmentService = serverEnvironmentService
        self.opener = opener
        self.configLoader = configLoader
    }

    func run(
        organizationName: String,
        directory: String?
    ) async throws {
        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(
                validating: directory, relativeTo: FileHandler.shared.currentPath
            )
        } else {
            directoryPath = FileHandler.shared.currentPath
        }
        let config = try await configLoader.loadConfig(path: directoryPath)
        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        try opener.open(
            url:
            serverURL
                .appendingPathComponent(organizationName)
                .appendingPathComponent("billing")
        )
    }
}
