import Foundation
import TuistCloud
import TuistCore
import TuistLoader
import TuistSupport

protocol CloudSessionServicing: AnyObject {
    /// It reads the cloud URL from the project's Config.swift and
    /// prints any existing session in the keychain to authenticate
    /// on a server identified by that URL.
    func printSession() throws
}

enum CloudSessionServiceError: FatalError, Equatable {
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

final class CloudSessionService: CloudSessionServicing {
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

    func printSession() throws {
        let path = FileHandler.shared.currentPath
        let config = try configLoader.loadConfig(path: path)
        guard let cloudURL = config.cloud?.url else {
            throw CloudSessionServiceError.missingCloudURL
        }
        try cloudSessionController.printSession(serverURL: cloudURL)
    }
}
