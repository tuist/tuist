import Foundation
import TuistCore
import TuistLab
import TuistLoader
import TuistSupport

protocol LabAuthServicing: AnyObject {
    /// It reads the lab URL from the project's Config.swift and
    /// authenticates the user on that server storing the credentials
    /// locally on the keychain
    func authenticate() throws
}

enum LabAuthServiceError: FatalError, Equatable {
    case missingLabURL

    /// Error description.
    var description: String {
        switch self {
        case .missingLabURL:
            return "The lab URL attribute is missing in your project's configuration."
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .missingLabURL:
            return .abort
        }
    }
}

final class LabAuthService: LabAuthServicing {
    let labSessionController: LabSessionControlling
    let configLoader: ConfigLoading

    // MARK: - Init

    convenience init() {
        let manifestLoader = ManifestLoader()
        let configLoader = ConfigLoader(manifestLoader: manifestLoader)
        self.init(
            labSessionController: LabSessionController(),
            configLoader: configLoader
        )
    }

    init(
        labSessionController: LabSessionControlling,
        configLoader: ConfigLoading
    ) {
        self.labSessionController = labSessionController
        self.configLoader = configLoader
    }

    // MARK: - LabAuthServicing

    func authenticate() throws {
        let path = FileHandler.shared.currentPath
        let config = try configLoader.loadConfig(path: path)
        guard let labURL = config.lab?.url else {
            throw LabAuthServiceError.missingLabURL
        }
        try labSessionController.authenticate(serverURL: labURL)
    }
}
