import Foundation
import TSCBasic
import TuistGraph
import TuistSupport
@testable import TuistCore

public final class MockCacheDirectoriesProviderFactory: CacheDirectoriesProviderFactoring {
    public var cacheDirectoriesStub: (() -> CacheDirectoriesProviding)?
    private let provider: CacheDirectoriesProviding

    public init(provider: CacheDirectoriesProviding) {
        self.provider = provider
    }

    public func cacheDirectories() -> CacheDirectoriesProviding {
        cacheDirectoriesStub?() ?? provider
    }
}
