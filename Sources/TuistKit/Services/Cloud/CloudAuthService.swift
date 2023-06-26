import Foundation
import TuistCloud
import TuistCore
import TuistLoader
import TuistSupport

public protocol CloudAuthServicing: AnyObject {
    /// It reads the cloud URL from the project's Config.swift and
    /// authenticates the user on that server storing the credentials
    /// locally on the keychain
    func authenticate() throws
}

public enum CloudAuthServiceError: FatalError, Equatable {
    case missingCloudURL

    /// Error description.
    public var description: String {
        switch self {
        case .missingCloudURL:
            return "The cloud URL attribute is missing in your project's configuration."
        }
    }

    /// Error type.
    public var type: ErrorType {
        switch self {
        case .missingCloudURL:
            return .abort
        }
    }
}

public final class CloudAuthService: CloudAuthServicing {
    let cloudSessionController: CloudSessionControlling
    let configLoader: ConfigLoading

    // MARK: - Init

    public convenience init() {
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

    public func authenticate() throws {
        let path = FileHandler.shared.currentPath
        let config = try configLoader.loadConfig(path: path)
        guard let cloudURL = config.cloud?.url else {
            throw CloudAuthServiceError.missingCloudURL
        }
        try cloudSessionController.authenticate(serverURL: cloudURL)
    }
}
