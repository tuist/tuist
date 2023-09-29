import Foundation
import TuistCloud

public final class MockGetCacheService: GetCacheServicing {
    public init() {}

    public var getCacheStub: ((URL, String, String, String) async throws -> CloudCacheArtifact)?
    public func getCache(
        serverURL: URL,
        projectId: String,
        hash: String,
        name: String
    ) async throws -> CloudCacheArtifact {
        try await getCacheStub?(
            serverURL,
            projectId,
            hash,
            name
        ) ?? .test()
    }
}
