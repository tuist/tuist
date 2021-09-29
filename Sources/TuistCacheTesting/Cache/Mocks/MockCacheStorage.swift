import Foundation
import RxSwift
import TSCBasic
import TuistCache
import TuistCore

public final class MockCacheStorage: CacheStoring {
    var existsStub: ((String, String) throws -> Bool)?

    public init() {}

    public func exists(name: String, hash: String) -> Single<Bool> {
        do {
            if let existsStub = existsStub {
                return Single.just(try existsStub(name, hash))
            } else {
                return Single.just(false)
            }
        } catch {
            return Single.error(error)
        }
    }

    var fetchStub: ((String, String) throws -> AbsolutePath)?
    public func fetch(name: String, hash: String) -> Single<AbsolutePath> {
        if let fetchStub = fetchStub {
            do {
                return Single.just(try fetchStub(name, hash))
            } catch {
                return Single.error(error)
            }
        } else {
            return Single.just(AbsolutePath.root)
        }
    }

    var storeStub: ((String, String, [AbsolutePath]) -> Void)?
    public func store(name: String, hash: String, paths: [AbsolutePath]) -> Completable {
        if let storeStub = storeStub {
            storeStub(name, hash, paths)
        }
        return Completable.empty()
    }
}
