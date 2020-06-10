import Foundation
import RxSwift
import TSCBasic
import TuistCache
import TuistCore

public final class MockCacheStorage: CacheStoring {
    var existsStub: ((String) -> Bool)?

    public init() {}

    public func exists(hash: String, config _: Config) -> Single<Bool> {
        if let existsStub = existsStub {
            return Single.just(existsStub(hash))
        } else {
            return Single.just(false)
        }
    }

    var fetchStub: ((String) throws -> AbsolutePath)?
    public func fetch(hash: String, config _: Config) -> Single<AbsolutePath> {
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

    var storeStub: ((_ hash: String, _ config: Config, _ xcframeworkPath: AbsolutePath) -> Void)?
    public func store(hash: String, config: Config, xcframeworkPath: AbsolutePath) -> Completable {
        if let storeStub = storeStub {
            storeStub(hash, config, xcframeworkPath)
        }
        return Completable.empty()
    }
}
