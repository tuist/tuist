import Foundation
import TSCBasic
import TuistCore
import TuistDependencies
import TuistLoader
import TuistSupport

final class DependenciesService {
    private let dependenciesController: DependenciesControlling
    private let dependenciesModelLoader: DependenciesModelLoading

    init(dependenciesController: DependenciesControlling = DependenciesController(),
         dependenciesModelLoader: DependenciesModelLoading = DependenciesModelLoader())
    {
        self.dependenciesController = dependenciesController
        self.dependenciesModelLoader = dependenciesModelLoader
    }

    func run(path: String?, method: InstallDependenciesMethod) throws {
        switch method {
        case .fetch: logger.info("Start fetching dependencies.", metadata: .section)
        case .update: logger.info("Start updating dependencies.", metadata: .section)
        }

        let path = self.path(path)

        let dependencies = try dependenciesModelLoader.loadDependencies(at: path)
        try dependenciesController.install(at: path, method: method, dependencies: dependencies)

        switch method {
        case .fetch: logger.info("Dependencies were fetched successfully.", metadata: .success)
        case .update: logger.info("Dependencies were updated successfully.", metadata: .success)
        }
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
