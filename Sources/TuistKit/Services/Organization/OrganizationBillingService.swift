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
        let config = try configLoader.loadConfig(path: directoryPath)
        let cloudURL = try serverURLService.url(configServerURL: config.cloud?.url)
        try opener.open(
            url: cloudURL
                .appendingPathComponent(organizationName)
                .appendingPathComponent("billing")
        )
    }
}
