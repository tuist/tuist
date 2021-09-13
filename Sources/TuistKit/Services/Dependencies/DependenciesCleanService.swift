import TSCBasic
import TuistSupport

final class DependenciesCleanService {
    func run(path: String?) throws {
        let path = self.path(path)
        let dependenciesPath = path.appending(components: [Constants.tuistDirectoryName, Constants.DependenciesDirectory.name])
        if FileHandler.shared.exists(dependenciesPath) {
            try FileHandler.shared.delete(dependenciesPath)
        }
        logger.info("Successfully cleaned dependencies at path \(dependenciesPath.pathString)", metadata: .success)
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
