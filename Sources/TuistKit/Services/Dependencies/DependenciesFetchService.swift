import Foundation
import TSCBasic
import TuistCore
import TuistDependencies
import TuistSupport

final class DependenciesFetchService {
    private let dependenciesController: DependenciesControlling

    init(dependenciesController: DependenciesControlling = DependenciesController()) {
        self.dependenciesController = dependenciesController
    }

    func run(path: String?) throws {
        let path = self.path(path)
        try dependenciesController.install(at: path, method: .fetch)
        logger.notice("Successfully fetched dependencies", metadata: .success)
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
