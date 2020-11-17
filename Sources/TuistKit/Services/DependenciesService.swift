import Foundation
import TSCBasic
import TuistCore
import TuistDependencies
import TuistLoader
import TuistSupport

final class DependenciesService {
    private let dependenciesController: DependenciesControlling
    private let manifestLoader: ManifestLoading

    init(dependenciesController: DependenciesControlling = DependenciesController(),
         manifestLoader: ManifestLoading = ManifestLoader()) {
        self.dependenciesController = dependenciesController
        self.manifestLoader = manifestLoader
    }

    func run(path: String?, method: InstallDependenciesMethod) throws {
        logger.notice("Start installing dependencies.")
        
        let path = self.path(path)
        
        let dependencies = try manifestLoader.loadDependencies(at: path).dependencies
        let carthageDependencies = dependencies
            .filter { $0.manager == .carthage }
            .map { CarthageDependency }
        
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
