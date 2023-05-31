import Foundation
import TuistCloud

public final class MockCleanRemoteCacheStorageService: CleanRemoteCacheStorageServicing {
    public init() {}

    public var cleanRemoteCacheStorageStub: ((URL, String) async throws -> Void)?
    public func cleanRemoteCacheStorage(serverURL: URL, projectSlug: String) async throws {
        try await cleanRemoteCacheStorageStub?(serverURL, projectSlug)
    }
}
