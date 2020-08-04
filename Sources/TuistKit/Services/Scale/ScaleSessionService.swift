import Foundation
import TuistCore
import TuistLoader
import TuistScale
import TuistSupport

protocol ScaleSessionServicing: AnyObject {
    /// It reads the scale URL from the project's Config.swift and
    /// prints any existing session in the keychain to authenticate
    /// on a server identified by that URL.
    func printSession() throws
}

enum ScaleSessionServiceError: FatalError, Equatable {
    case missingScaleURL

    /// Error description.
    var description: String {
        switch self {
        case .missingScaleURL:
            return "The scale URL attribute is missing in your project's configuration."
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .missingScaleURL:
            return .abort
        }
    }
}

final class ScaleSessionService: ScaleSessionServicing {
    /// Scale session controller.
    let scaleSessionController: ScaleSessionControlling

    /// Generator model loader.
    let generatorModelLoader: GeneratorModelLoading

    // MARK: - Init

    convenience init() {
        let manifetLoader = ManifestLoader()
        let manifestLinter = ManifestLinter()
        let generatorModelLoader = GeneratorModelLoader(manifestLoader: manifetLoader,
                                                        manifestLinter: manifestLinter)
        self.init(scaleSessionController: ScaleSessionController(),
                  generatorModelLoader: generatorModelLoader)
    }

    init(scaleSessionController: ScaleSessionControlling,
         generatorModelLoader: GeneratorModelLoading)
    {
        self.scaleSessionController = scaleSessionController
        self.generatorModelLoader = generatorModelLoader
    }

    // MARK: - ScaleAuthServicing

    func printSession() throws {
        let path = FileHandler.shared.currentPath
        let config = try generatorModelLoader.loadConfig(at: path)
        guard let scaleURL = config.scale?.url else {
            throw ScaleSessionServiceError.missingScaleURL
        }
        try scaleSessionController.printSession(serverURL: scaleURL)
    }
}
