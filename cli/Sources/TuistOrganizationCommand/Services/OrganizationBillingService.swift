import Foundation
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistOpener
import TuistServer

protocol OrganizationBillingServicing {
    func run(
        organizationName: String,
        directory: String?
    ) async throws
}

struct OrganizationBillingService: OrganizationBillingServicing {
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
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(directory)
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
