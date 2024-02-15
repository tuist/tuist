import Foundation
import TSCBasic
import TuistSupport
@testable import TuistCore

public final class MockCacheDirectoriesProvider: CacheDirectoriesProviding {
    private let directory: TemporaryDirectory

    public init() throws {
        directory = try TemporaryDirectory(removeTreeOnDeinit: true)
    }

    private var _tuistCacheDirectory: AbsolutePath {
        tuistCacheDirectoryStub ?? directory.path.appending(component: "TuistCache")
    }

    private var _cacheDirectory: AbsolutePath {
        cacheDirectoryStub ?? directory.path
    }

    public var tuistCacheDirectoryStub: AbsolutePath?
    public func tuistCacheDirectory(for category: TuistCore.CacheCategory) throws -> TSCBasic.AbsolutePath {
        _tuistCacheDirectory.appending(component: category.directoryName)
    }

    public var cacheDirectoryStub: AbsolutePath?
    public func cacheDirectory() throws -> AbsolutePath {
        return _cacheDirectory
    }
}
