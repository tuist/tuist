import Foundation
import RxSwift
import TSCBasic
import TuistCache
import TuistCore

public final class MockCacheStorage: CacheStoraging {
    var existsStub: ((String) -> Bool)?

    public init() {}

    public func exists(hash: String, userConfig: Config) -> Single<Bool> {
        if let existsStub = existsStub {
            return Single.just(existsStub(hash))
        } else {
            return Single.just(false)
        }
    }

    var fetchStub: ((String) throws -> AbsolutePath)?
    public func fetch(hash: String, userConfig: Config) -> Single<AbsolutePath> {
        if let fetchStub = fetchStub {
            do {
                return Single.just(try fetchStub(hash))
            } catch {
                return Single.error(error)
            }
        } else {
            return Single.just(AbsolutePath.root)
        }
    }

    var storeStub: ((_ hash: String, _ userConfig: Config, _ xcframeworkPath: AbsolutePath) -> Void)?
    public func store(hash: String, userConfig: Config, xcframeworkPath: AbsolutePath) -> Completable {
        if let storeStub = storeStub {
            storeStub(hash, userConfig, xcframeworkPath)
        }
        return Completable.empty()
    }
}
