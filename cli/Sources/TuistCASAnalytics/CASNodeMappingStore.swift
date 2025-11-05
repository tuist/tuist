import Foundation

/// Protocol for storing and retrieving CAS node ID to checksum mappings
public protocol CASNodeMappingStoring: Sendable {
    /// Store a mapping between a node ID and checksum hex
    func storeNode(_ nodeID: String, checksum: String) async throws
    
    /// Retrieve checksum hex for a given node ID
    func checksum(for nodeID: String) async throws -> String?
}