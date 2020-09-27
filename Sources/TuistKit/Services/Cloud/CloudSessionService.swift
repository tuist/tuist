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
    /// Cloud session controller.
    let cloudSessionController: CloudSessionControlling

    /// Generator model loader.
    let generatorModelLoader: GeneratorModelLoading

    // MARK: - Init

    convenience init() {
        let manifetLoader = ManifestLoader()
        let manifestLinter = ManifestLinter()
        let generatorModelLoader = GeneratorModelLoader(manifestLoader: manifetLoader,
                                                        manifestLinter: manifestLinter)
        self.init(cloudSessionController: CloudSessionController(),
                  generatorModelLoader: generatorModelLoader)
    }

    init(cloudSessionController: CloudSessionControlling,
         generatorModelLoader: GeneratorModelLoading)
    {
        self.cloudSessionController = cloudSessionController
        self.generatorModelLoader = generatorModelLoader
    }

    // MARK: - CloudAuthServicing

    func printSession() throws {
        let path = FileHandler.shared.currentPath
        let config = try generatorModelLoader.loadConfig(at: path)
        guard let cloudURL = config.cloud?.url else {
            throw CloudSessionServiceError.missingCloudURL
        }
        try cloudSessionController.printSession(serverURL: cloudURL)
    }
}
