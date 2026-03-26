import Foundation
import Mockable

public enum KeyValueOperationType: String, Codable {
    case read
    case write
}

/// Protocol for storing and retrieving KeyValue metadata
@Mockable
public protocol KeyValueMetadataStoring: Sendable {
    /// Store metadata for a KeyValue operation identified by cache key
    func storeMetadata(_ metadata: KeyValueMetadata, for cacheKey: String, operationType: KeyValueOperationType) async throws

    /// Retrieve metadata for a KeyValue operation
    func metadata(for cacheKey: String, operationType: KeyValueOperationType) async throws -> KeyValueMetadata?
}

public struct KeyValueMetadataStore: KeyValueMetadataStoring {
    private let database: CASAnalyticsDatabasing

    public init(database: CASAnalyticsDatabasing = CASAnalyticsDatabase.shared) {
        self.database = database
    }

    public func storeMetadata(
        _ metadata: KeyValueMetadata,
        for cacheKey: String,
        operationType: KeyValueOperationType
    ) async throws {
        let sanitizedKey = sanitizeCacheKey(cacheKey)
        let jsonData = try JSONEncoder().encode(metadata)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        try database.storeKeyValueMetadata(key: sanitizedKey, operationType: operationType.rawValue, value: jsonString)
    }

    public func metadata(for cacheKey: String, operationType: KeyValueOperationType) async throws -> KeyValueMetadata? {
        let sanitizedKey = sanitizeCacheKey(cacheKey)
        guard let jsonString = try database.keyValueMetadata(for: sanitizedKey, operationType: operationType.rawValue) else {
            return nil
        }
        return try JSONDecoder().decode(KeyValueMetadata.self, from: jsonString.data(using: .utf8)!)
    }

    private func sanitizeCacheKey(_ cacheKey: String) -> String {
        cacheKey.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "~", with: "_")
    }
}
