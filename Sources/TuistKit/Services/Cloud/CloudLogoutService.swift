import Foundation
import TuistCloud
import TuistCore
import TuistLoader
import TuistSupport

protocol CloudLogoutServicing: AnyObject {
    /// It reads the cloud URL from the project's Config.swift and
    /// and it removes any session associated to that domain from
    /// the keychain
    func logout() throws
}

enum CloudLogoutServiceError: FatalError, Equatable {
    case missingCloudURL

    /// Error description.
    var description: String {
        switch self {
        case .missingCloudURL:
            return "The cloud URL attribute is missing in your project's configuration."
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .missingCloudURL:
            return .abort
        }
    }
}

final class CloudLogoutService: CloudLogoutServicing {
    let cloudSessionController: CloudSessionControlling
    let configLoader: ConfigLoading

    // MARK: - Init

    convenience init() {
        let manifestLoader = ManifestLoader()
        let configLoader = ConfigLoader(manifestLoader: manifestLoader)
        self.init(
            cloudSessionController: CloudSessionController(),
            configLoader: configLoader
        )
    }

    init(
        cloudSessionController: CloudSessionControlling,
        configLoader: ConfigLoading
    ) {
        self.cloudSessionController = cloudSessionController
        self.configLoader = configLoader
    }

    // MARK: - CloudAuthServicing

    func logout() throws {
        let path = FileHandler.shared.currentPath
        let config = try configLoader.loadConfig(path: path)
        guard let cloudURL = config.cloud?.url else {
            throw CloudLogoutServiceError.missingCloudURL
        }
        try cloudSessionController.logout(serverURL: cloudURL)
    }
}
