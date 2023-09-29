import Foundation
import TuistCloud

public final class MockUploadCacheService: UploadCacheServicing {
    public init() {}

    public var uploadCacheStub: ((URL, String, String, String, String) async throws -> CloudCacheArtifact)?
    public func uploadCache(
        serverURL: URL,
        projectId: String,
        hash: String,
        name: String,
        contentMD5: String
    ) async throws -> CloudCacheArtifact {
        try await uploadCacheStub?(
            serverURL,
            projectId,
            hash,
            name,
            contentMD5
        ) ?? .test()
    }
}
