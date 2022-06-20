import Foundation
import TSCBasic
import TuistCache
import TuistCore

public final class MockCacheStorage: CacheStoring {
    var existsStub: ((String, String) throws -> Bool)?

    public init() {}

    public func exists(name: String, hash: String) async throws -> Bool {
        try existsStub?(name, hash) ?? false
    }

    var fetchStub: ((String, String) throws -> AbsolutePath?)?
    public func fetch(name: String, hash: String) async throws -> AbsolutePath? {
        guard let fetchStub = fetchStub else {
            return .root
        }
        return try fetchStub(name, hash)
    }

    var storeStub: ((String, String, [AbsolutePath]) -> Void)?
    public func store(name: String, hash: String, paths: [AbsolutePath]) async throws {
        storeStub?(name, hash, paths)
    }
}
