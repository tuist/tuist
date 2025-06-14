import Foundation
import Path
import TuistCore
import TuistSupport

/// `CachedContentHasher`
/// is a wrapper on top of `ContentHasher` that adds an in-memory cache to avoid re-computing the same hashes
public final class CachedContentHasher: ContentHashing {
    private let contentHasher: ContentHashing

    /// In memory cache for files that have already been hashed.
    private var hashesCache: ThreadSafe<[AbsolutePath: String]> = ThreadSafe([:])

    public init(contentHasher: ContentHashing = ContentHasher()) {
        self.contentHasher = contentHasher
    }

    public func hash(_ data: Data) throws -> String {
        try contentHasher.hash(data)
    }

    public func hash(_ string: String) throws -> String {
        try contentHasher.hash(string)
    }

    public func hash(_ boolean: Bool) throws -> String {
        try contentHasher.hash(boolean)
    }

    public func hash(_ strings: [String]) throws -> String {
        try contentHasher.hash(strings)
    }

    public func hash(_ dictionary: [String: String]) throws -> String {
        try contentHasher.hash(dictionary)
    }

    public func hash(path filePath: AbsolutePath) async throws -> String {
        if let cachedHash = hashesCache.value[filePath] {
            return cachedHash
        }
        let hash = try await contentHasher.hash(path: filePath)
        hashesCache.mutate { $0[filePath] = hash }
        return hash
    }
}
