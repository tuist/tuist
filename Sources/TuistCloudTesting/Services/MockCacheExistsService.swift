import Foundation
import TuistCloud

public final class MockCacheExistsService: CacheExistsServicing {
    public init() {}

    // swiftlint:disable:next large_tuple
    public var cacheExistsStub: ((URL, String, String, String) async throws -> Void)?
    public func cacheExists(
        serverURL: URL,
        projectId: String,
        hash: String,
        name: String
    ) async throws {
        try await cacheExistsStub?(
            serverURL,
            projectId,
            hash,
            name
        )
    }
}
