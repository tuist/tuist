import Foundation
import TuistCloud
import TuistCore
import TuistLoader
import TuistSupport

protocol CloudAuthServicing: AnyObject {
    /// It reads the cloud URL from the project's Config.swift and
    /// authenticates the user on that server storing the credentials
    /// locally on the keychain
    func authenticate() throws
}

enum CloudAuthServiceError: FatalError, Equatable {
    case missingCloudURL

    /// Error description.
    var description: String {
        switch self {
        case .missingCloudURL:
            return "The cloudURL attribute is missing in your project's configuration."
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

final class CloudAuthService: CloudAuthServicing {
    let cloudSessionController: CloudSessionControlling
    let generatorModelLoader: GeneratorModelLoading
    let versionsFetcher: VersionsFetching

    // MARK: - Init

    convenience init() {
        let manifetLoader = ManifestLoader()
        let manifestLinter = ManifestLinter()
        let generatorModelLoader = GeneratorModelLoader(manifestLoader: manifetLoader,
                                                        manifestLinter: manifestLinter)
        self.init(cloudSessionController: CloudSessionController(),
                  generatorModelLoader: generatorModelLoader,
                  versionsFetcher: VersionsFetcher())
    }

    init(cloudSessionController: CloudSessionControlling,
         generatorModelLoader: GeneratorModelLoading,
         versionsFetcher: VersionsFetching) {
        self.cloudSessionController = cloudSessionController
        self.generatorModelLoader = generatorModelLoader
        self.versionsFetcher = versionsFetcher
    }

    // MARK: - CloudAuthServicing

    func authenticate() throws {
        let path = FileHandler.shared.currentPath
        let versions = try versionsFetcher.fetch()
        let config = try generatorModelLoader.loadConfig(at: path, versions: versions)
        guard let cloudURL = config.cloudURL else {
            throw CloudAuthServiceError.missingCloudURL
        }
        try cloudSessionController.authenticate(serverURL: cloudURL)
    }
}
