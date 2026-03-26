import Foundation
import Mockable

/// Protocol for storing and retrieving CAS node ID to checksum mappings
@Mockable
public protocol CASNodeStoring: Sendable {
    /// Store a mapping between a node ID and checksum hex
    func storeNode(_ nodeID: String, checksum: String) async throws

    /// Retrieve checksum hex for a given node ID
    func checksum(for nodeID: String) async throws -> String?
}

public struct CASNodeStore: CASNodeStoring {
    private let database: CASAnalyticsDatabasing

    public init(database: CASAnalyticsDatabasing = CASAnalyticsDatabase.shared) {
        self.database = database
    }

    public func storeNode(_ nodeID: String, checksum: String) async throws {
        let sanitizedNodeID = sanitizeNodeID(nodeID)
        try database.store(category: "nodes", key: sanitizedNodeID, value: checksum)
    }

    public func checksum(for nodeID: String) async throws -> String? {
        let sanitizedNodeID = sanitizeNodeID(nodeID)
        return try database.get(category: "nodes", key: sanitizedNodeID)
    }

    private func sanitizeNodeID(_ nodeID: String) -> String {
        nodeID.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }
}
