import Foundation
import TuistCloud

public final class MockCleanCacheService: CleanCacheServicing {
    public init() {}

    public var cleanCacheStub: ((URL, String) async throws -> Void)?
    public func cleanCache(serverURL: URL, fullName: String) async throws {
        try await cleanCacheStub?(serverURL, fullName)
    }
}
