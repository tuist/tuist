import FileSystem
import Mockable
import Path
import ServiceContextModule
import TuistSupport

@Mockable
public protocol CacheDirectoriesProviding {
    /// Returns the cache directory for a Tuist cache category
    func cacheDirectory(for category: CacheCategory) throws -> AbsolutePath
    func cacheDirectory() -> AbsolutePath
}

public final class CacheDirectoriesProvider: CacheDirectoriesProviding {
    private let fileHandler: FileHandling

    init(
        fileHandler: FileHandling,
    ) {
        self.fileHandler = fileHandler
    }

    public convenience init() {
        self.init(
            fileHandler: FileHandler.shared
        )
    }

    public func cacheDirectory(for category: CacheCategory) throws -> AbsolutePath {
        cacheDirectory().appending(component: category.directoryName)
    }

    public func cacheDirectory() -> Path.AbsolutePath {
        return ServiceContext.current!.environment!.cacheDirectory
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
    }
}
