import Foundation
import TSCBasic
import TuistCore
import TuistDependencies
import TuistLoader
import TuistSupport

final class DependenciesFetchService {
    private let dependenciesController: DependenciesControlling
    private let dependenciesModelLoader: DependenciesModelLoading

    init(dependenciesController: DependenciesControlling = DependenciesController(),
         dependenciesModelLoader: DependenciesModelLoading = DependenciesModelLoader())
    {
        self.dependenciesController = dependenciesController
        self.dependenciesModelLoader = dependenciesModelLoader
    }

    func run(path: String?) throws {
        logger.info("We are starting to fetch the dependencies.", metadata: .section)

        let path = self.path(path)
        let dependencies = try dependenciesModelLoader.loadDependencies(at: path)
        try dependenciesController.fetch(at: path, dependencies: dependencies)

        logger.info("Dependencies were fetched successfully.", metadata: .success)
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
