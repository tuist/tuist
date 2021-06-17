import Foundation
import TuistCore
import TuistLab
import TuistLoader
import TuistSupport

protocol LabSessionServicing: AnyObject {
    /// It reads the lab URL from the project's Config.swift and
    /// prints any existing session in the keychain to authenticate
    /// on a server identified by that URL.
    func printSession() throws
}

enum LabSessionServiceError: FatalError, Equatable {
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

final class LabSessionService: LabSessionServicing {
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

    func printSession() throws {
        let path = FileHandler.shared.currentPath
        let config = try configLoader.loadConfig(path: path)
        guard let labURL = config.lab?.url else {
            throw LabSessionServiceError.missingLabURL
        }
        try labSessionController.printSession(serverURL: labURL)
    }
}
