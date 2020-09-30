import Foundation
import RxSwift
import TSCBasic
import TuistCache
import TuistCore

public final class MockCacheStorage: CacheStoring {
    public init() {}

    public var invokedExists = false
    public var invokedExistsCount = 0
    public var invokedExistsParameters: (hash: String, Void)?
    public var invokedExistsParametersList = [(hash: String, Void)]()
    public var stubbedExistsResult: Single<Bool>!

    public func exists(hash: String) -> Single<Bool> {
        invokedExists = true
        invokedExistsCount += 1
        invokedExistsParameters = (hash, ())
        invokedExistsParametersList.append((hash, ()))
        return stubbedExistsResult
    }

    public var invokedFetch = false
    public var invokedFetchCount = 0
    public var invokedFetchParameters: (hash: String, Void)?
    public var invokedFetchParametersList = [(hash: String, Void)]()
    public var stubbedFetchResult: Single<AbsolutePath>!

    public func fetch(hash: String) -> Single<AbsolutePath> {
        invokedFetch = true
        invokedFetchCount += 1
        invokedFetchParameters = (hash, ())
        invokedFetchParametersList.append((hash, ()))
        return stubbedFetchResult
    }

    public var invokedStore = false
    public var invokedStoreCount = 0
    public var invokedStoreParameters: (hash: String, paths: [AbsolutePath])?
    public var invokedStoreParametersList = [(hash: String, paths: [AbsolutePath])]()
    public var stubbedStoreResult: Completable!

    public func store(hash: String, paths: [AbsolutePath]) -> Completable {
        invokedStore = true
        invokedStoreCount += 1
        invokedStoreParameters = (hash, paths)
        invokedStoreParametersList.append((hash, paths))
        return stubbedStoreResult
    }
}
