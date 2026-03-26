import Foundation
import Mockable

@Mockable
public protocol CASNodeStoring: Sendable {
    func storeNode(_ nodeID: String, checksum: String) async throws
    func checksum(for nodeID: String) async throws -> String?
}

public struct CASNodeStore: CASNodeStoring {
    private let database: CASAnalyticsDatabasing

    public init(database: CASAnalyticsDatabasing) {
        self.database = database
    }

    public func storeNode(_ nodeID: String, checksum: String) async throws {
        try database.storeNode(key: sanitize(nodeID), checksum: checksum)
    }

    public func checksum(for nodeID: String) async throws -> String? {
        try database.node(for: sanitize(nodeID))
    }

    private func sanitize(_ nodeID: String) -> String {
        nodeID.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }
}
