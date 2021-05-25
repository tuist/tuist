import Foundation
import TSCBasic
import TuistCore
import TuistDependencies
import TuistLoader
import TuistSupport

// MARK: - DependenciesUpdateService

final class DependenciesUpdateService {
    private let dependenciesController: DependenciesControlling
    private let dependenciesModelLoader: DependenciesModelLoading
    private let configLoading: ConfigLoading

    init(
        dependenciesController: DependenciesControlling = DependenciesController(),
        dependenciesModelLoader: DependenciesModelLoading = DependenciesModelLoader(),
        configLoading: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader())
    ) {
        self.dependenciesController = dependenciesController
        self.dependenciesModelLoader = dependenciesModelLoader
        self.configLoading = configLoading
    }

    func run(path: String?) throws {
        logger.info("Updating dependencies.", metadata: .section)

        let path = self.path(path)
        let dependencies = try dependenciesModelLoader.loadDependencies(at: path)

        let config = try configLoading.loadConfig(path: path)
        let swiftVersion = config.swiftVersion

        try dependenciesController.update(
            at: path,
            dependencies: dependencies,
            swiftVersion: swiftVersion
        )

        logger.info("Dependencies updated successfully.", metadata: .success)
    }

    // MARK: - Helpers

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
