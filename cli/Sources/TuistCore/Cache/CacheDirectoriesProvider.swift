import FileSystem
import Mockable
import Path
import TuistEnvironment
import TuistSupport

@Mockable
public protocol CacheDirectoriesProviding {
    /// Returns the cache directory for a Tuist cache category
    func cacheDirectory(for category: CacheCategory) throws -> AbsolutePath
    func cacheDirectory() -> AbsolutePath
}

public struct CacheDirectoriesProvider: CacheDirectoriesProviding {
    public init() {}

    public func cacheDirectory(for category: CacheCategory) throws -> AbsolutePath {
        cacheDirectory().appending(component: category.directoryName)
    }

    public func cacheDirectory() -> Path.AbsolutePath {
        Environment.current.cacheDirectory
    }

    public static func bootstrap() async throws {
        let fileSystem = FileSystem()
        let provider = CacheDirectoriesProvider()
        for category in CacheCategory.allCases {
            let directory = try provider.cacheDirectory(for: category)
            if try await !fileSystem.exists(directory) {
                try await fileSystem.makeDirectory(at: directory)
            }
        }
        // Here rather than in a command, so that no entry point can grow a cache nothing prunes,
        // and awaited rather than detached, so retention runs before anything resolves an entry it
        // could reclaim. Cache maintenance never fails the command it runs ahead of.
        try? await SupportCachePruner(cacheDirectoriesProvider: provider, fileSystem: fileSystem).prune()
    }
}
