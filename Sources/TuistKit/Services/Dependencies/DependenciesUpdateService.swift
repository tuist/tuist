import Foundation
import TSCBasic
import TuistCore
import TuistDependencies
import TuistLoader
import TuistSupport

// MARK: - DependenciesUpdateService

final class DependenciesUpdateService {
    private let dependenciesController: DependenciesControlling
    private let dependenciesService: DependenciesServicing
    private let configLoading: ConfigLoading
    private let converter: ManifestModelConverting

    init(
        dependenciesController: DependenciesControlling = DependenciesController(),
        dependenciesService: DependenciesServicing = DependenciesService(),
        configLoading: ConfigLoading = ConfigLoader(manifestLoader: ManifestLoader()),
        converter: ManifestModelConverting = ManifestModelConverter()
    ) {
        self.dependenciesController = dependenciesController
        self.dependenciesService = dependenciesService
        self.configLoading = configLoading
        self.converter = converter
    }

    func run(path: String?) throws {
        logger.info("Updating dependencies.", metadata: .section)

        let path = self.path(path)
        let config = try configLoading.loadConfig(path: path)
        let dependencies = try dependenciesService.loadDependencies(at: path, using: config)
        let swiftVersion = config.swiftVersion

        let dependenciesManifest = try dependenciesController.update(
            at: path,
            dependencies: dependencies,
            swiftVersion: swiftVersion
        )

        let dependenciesGraph = try converter.convert(manifest: dependenciesManifest, path: path)

        try dependenciesController.save(
            dependenciesGraph: dependenciesGraph,
            to: path
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
