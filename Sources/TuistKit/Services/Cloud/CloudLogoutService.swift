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

final class CloudLogoutService: CloudLogoutServicing {
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

    func logout() throws {
        let path = FileHandler.shared.currentPath
        let versions = try versionsFetcher.fetch()
        let config = try generatorModelLoader.loadConfig(at: path, versions: versions)

        guard let cloudURL = config.cloudURL else {
            throw CloudLogoutServiceError.missingCloudURL
        }
        try cloudSessionController.logout(serverURL: cloudURL)
    }
}
