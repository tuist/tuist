import Foundation
import Mockable
import Path
import TuistSupport
import XcodeGraph

@Mockable
public protocol CacheDirectoriesProviding {
    /// Returns the cache directory for a Tuist cache category
    func cacheDirectory(for category: CacheCategory) throws -> AbsolutePath
    func cacheDirectory() -> AbsolutePath
}

public final class CacheDirectoriesProvider: CacheDirectoriesProviding {
    private let fileHandler: FileHandling
    private let environment: Environmenting

    init(
        fileHandler: FileHandling,
        environment: Environmenting
    ) {
        self.fileHandler = fileHandler
        self.environment = environment
    }

    public convenience init() {
        self.init(
            fileHandler: FileHandler.shared,
            environment: Environment.shared
        )
    }

    public func cacheDirectory(for category: CacheCategory) throws -> AbsolutePath {
        cacheDirectory().appending(components: ["tuist", category.directoryName])
    }

    public func cacheDirectory() -> Path.AbsolutePath {
        if let cacheDirectory = environment.cacheDirectory {
            return cacheDirectory
        } else {
            return FileHandler.shared.homeDirectory.appending(components: ".cache")
        }
    }
}
