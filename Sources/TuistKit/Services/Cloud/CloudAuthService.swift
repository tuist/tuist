import Foundation
import Mockable
import Path
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport

@Mockable
protocol CloudAuthServicing: AnyObject {
    func authenticate(
        directory: String?
    ) async throws
}

final class CloudAuthService: CloudAuthServicing {
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

    // MARK: - CloudAuthServicing

    func authenticate(
        directory: String?
    ) async throws {
        let directoryPath: AbsolutePath
        if let directory {
            directoryPath = try AbsolutePath(validating: directory, relativeTo: FileHandler.shared.currentPath)
        } else {
            directoryPath = FileHandler.shared.currentPath
        }
        let config = try configLoader.loadConfig(path: directoryPath)
        let cloudURL = try cloudURLService.url(configCloudURL: config.cloud?.url)
        try await cloudSessionController.authenticate(serverURL: cloudURL)
    }
}
