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
         dependenciesModelLoader: DependenciesModelLoading = DependenciesModelLoader()) {
        self.dependenciesController = dependenciesController
        self.dependenciesModelLoader = dependenciesModelLoader
    }

    func run(path: String?, method: InstallDependenciesMethod) throws {
        logger.notice("Start installing dependencies.")
        
        let path = self.path(path)
        
        let carthageDependencies = try dependenciesModelLoader.loadDependencies(at: path)
        try dependenciesController.install(at: path, method: method, carthageDependencies: carthageDependencies)
        
        logger.notice("Successfully installed dependencies.", metadata: .success)
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
