import Foundation
import Mockable

public enum KeyValueOperationType: String, Codable {
    case read
    case write
}

@Mockable
public protocol KeyValueMetadataStoring: Sendable {
    func storeMetadata(_ metadata: KeyValueMetadata, for cacheKey: String, operationType: KeyValueOperationType) async throws
    func metadata(for cacheKey: String, operationType: KeyValueOperationType) async throws -> KeyValueMetadata?
}

public struct KeyValueMetadataStore: KeyValueMetadataStoring {
    private let database: CASAnalyticsDatabasing

    public init(database: CASAnalyticsDatabasing) {
        self.database = database
    }

    public func storeMetadata(
        _ metadata: KeyValueMetadata,
        for cacheKey: String,
        operationType: KeyValueOperationType
    ) async throws {
        try database.storeKeyValueMetadata(
            key: sanitize(cacheKey),
            operationType: operationType.rawValue,
            duration: metadata.duration
        )
    }

    public func metadata(for cacheKey: String, operationType: KeyValueOperationType) async throws -> KeyValueMetadata? {
        try database.keyValueMetadata(for: sanitize(cacheKey), operationType: operationType.rawValue)
    }

    private func sanitize(_ cacheKey: String) -> String {
        cacheKey.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "~", with: "_")
    }
}
