import Foundation
import TSCBasic
import TuistSupport

final class CacheService {
    /// Cache controller.
    private let cacheController: CacheControlling

    init(cacheController: CacheControlling = CacheController()) {
        self.cacheController = cacheController
    }

    func run(path: String?) throws {
        let path = self.path(path)
        try cacheController.cache(path: path)
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
