import Foundation
import Basic

/// CacheContentHasher is a wrapper on top of ContentHasher that adds an in-memory cache to avoid recalculating the same hashes
final class CacheContentHasher: ContentHashing {
    private let contentHasher: ContentHashing

    /// In memory cache for files that have already been hashed
    private var hashesCache: [String: String] = [:]

    init(contentHasher: ContentHashing = ContentHasher()) {
        self.contentHasher = contentHasher
    }

    func hash(_ string: String) throws -> String {
        if let cachedHash = hashesCache[string] {
            return cachedHash
        }
        let hash = try contentHasher.hash(string)
        hashesCache[string] = hash
        return hash
    }

    func hash(_ strings: Array<String>) throws -> String {
        let key = strings.joined()
        if let cachedHash = hashesCache[key] {
              return cachedHash
        }
        let hash = try contentHasher.hash(strings)
        hashesCache[key] = hash
        return hash
    }
    
    func hash(fileAtPath filePath: AbsolutePath) throws -> String {
        if let cachedHash = hashesCache[filePath.pathString] {
            return cachedHash
        }
        let hash = try contentHasher.hash(fileAtPath: filePath)
        hashesCache[filePath.pathString] = hash
        return hash
    }
}
