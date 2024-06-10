import Foundation
import Path
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport

protocol CloudLogoutServicing: AnyObject {
    /// It removes any session associated to that domain from
    /// the keychain
    func logout(
        directory: String?
    ) throws
}

final class CloudLogoutService: CloudLogoutServicing {
    private let cloudSessionController: CloudSessionControlling
    private let cloudURLService: CloudURLServicing
    private let configLoader: ConfigLoading

    init(
        cloudSessionController: CloudSessionControlling = CloudSessionController(),
        cloudURLService: CloudURLServicing = CloudURLService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.cloudSessionController = cloudSessionController
        self.cloudURLService = cloudURLService
        self.configLoader = configLoader
    }

    func logout(
        directory: String?
    ) throws {
        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(validating: directory, relativeTo: FileHandler.shared.currentPath)
        } else {
            directoryPath = FileHandler.shared.currentPath
        }
        let config = try configLoader.loadConfig(path: directoryPath)
        let cloudURL = try cloudURLService.url(configCloudURL: config.cloud?.url)
        try cloudSessionController.logout(serverURL: cloudURL)
    }
}
