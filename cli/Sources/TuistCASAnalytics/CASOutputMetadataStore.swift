import Foundation
import Mockable

@Mockable
public protocol CASOutputMetadataStoring: Sendable {
    func storeMetadata(_ metadata: CASOutputMetadata, for casID: String) async throws
    func metadata(for casID: String) async throws -> CASOutputMetadata?
}

public struct CASOutputMetadataStore: CASOutputMetadataStoring {
    private let database: CASAnalyticsDatabasing

    public init(database: CASAnalyticsDatabasing = CASAnalyticsDatabase.current) {
        self.database = database
    }

    public func storeMetadata(_ metadata: CASOutputMetadata, for casID: String) async throws {
        try database.storeCASOutput(
            key: sanitize(casID),
            size: metadata.size,
            duration: metadata.duration,
            compressedSize: metadata.compressedSize
        )
    }

    public func metadata(for casID: String) async throws -> CASOutputMetadata? {
        try database.casOutput(for: sanitize(casID))
    }

    private func sanitize(_ casID: String) -> String {
        casID.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "~", with: "_")
    }
}
