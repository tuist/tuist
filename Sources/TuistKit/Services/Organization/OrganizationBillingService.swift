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
    private let serverURLService: ServerURLServicing
    private let opener: Opening
    private let configLoader: ConfigLoading

    init(
        serverURLService: ServerURLServicing = ServerURLService(),
        opener: Opening = Opener(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.serverURLService = serverURLService
        self.opener = opener
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
        try opener.open(
            url: serverURL
                .appendingPathComponent(organizationName)
                .appendingPathComponent("billing")
        )
    }
}
