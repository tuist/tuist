import Basic
import Foundation
import RxSwift
import TuistCore
import TuistGalaxy

public final class MockCacheStorage: CacheStoraging {
    var existsStub: ((String) -> Bool)?
    public func exists(hash: String) -> Single<Bool> {
        if let existsStub = existsStub {
            return Single.just(existsStub(hash))
        } else {
            return Single.just(false)
        }
    }

    var fetchStub: ((String) -> AbsolutePath)?
    public func fetch(hash: String) -> Single<AbsolutePath> {
        if let fetchStub = fetchStub {
            return Single.just(fetchStub(hash))
        } else {
            return Single.just(AbsolutePath.root)
        }
    }

    var storeStub: ((_ hash: String, _ xcframeworkPath: AbsolutePath) -> Void)?
    public func store(hash: String, xcframeworkPath: AbsolutePath) -> Completable {
        if let storeStub = storeStub {
            storeStub(hash, xcframeworkPath)
        }
        return Completable.empty()
    }
}
