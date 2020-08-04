import Foundation
import TuistCore
import TuistLoader
import TuistScale
import TuistSupport

protocol ScaleAuthServicing: AnyObject {
    /// It reads the scale URL from the project's Config.swift and
    /// authenticates the user on that server storing the credentials
    /// locally on the keychain
    func authenticate() throws
}

enum ScaleAuthServiceError: FatalError, Equatable {
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

final class ScaleAuthService: ScaleAuthServicing {
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

    // MARK: - CloudAuthServicing

    func authenticate() throws {
        let path = FileHandler.shared.currentPath
        let config = try generatorModelLoader.loadConfig(at: path)
        guard let scaleURL = config.scale?.url else {
            throw ScaleAuthServiceError.missingScaleURL
        }
        try scaleSessionController.authenticate(serverURL: scaleURL)
    }
}
