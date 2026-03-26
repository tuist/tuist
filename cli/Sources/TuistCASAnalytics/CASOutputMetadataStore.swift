import Foundation
import Mockable

/// Protocol for storing and retrieving CAS output metadata
@Mockable
public protocol CASOutputMetadataStoring: Sendable {
    /// Store metadata for a CAS output identified by CAS ID
    func storeMetadata(_ metadata: CASOutputMetadata, for casID: String) async throws

    /// Retrieve metadata for a CAS output
    func metadata(for casID: String) async throws -> CASOutputMetadata?
}

public struct CASOutputMetadataStore: CASOutputMetadataStoring {
    private let database: CASAnalyticsDatabasing

    public init(database: CASAnalyticsDatabasing) {
        self.database = database
    }

    public func storeMetadata(_ metadata: CASOutputMetadata, for casID: String) async throws {
        let sanitizedCasID = sanitizeCasID(casID)
        let jsonData = try JSONEncoder().encode(metadata)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        try database.store(category: "cas", key: sanitizedCasID, value: jsonString)
    }

    public func metadata(for casID: String) async throws -> CASOutputMetadata? {
        let sanitizedCasID = sanitizeCasID(casID)
        guard let jsonString = try database.get(category: "cas", key: sanitizedCasID) else {
            return nil
        }
        return try JSONDecoder().decode(CASOutputMetadata.self, from: jsonString.data(using: .utf8)!)
    }

    private func sanitizeCasID(_ casID: String) -> String {
        casID.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "~", with: "_")
    }
}
