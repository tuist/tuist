@preconcurrency import FileSystem
import Foundation
import Mockable
import Path
import TuistSupport

/// Protocol for storing and retrieving CAS node ID to checksum mappings
@Mockable
public protocol CASNodeStoring: Sendable {
    /// Store a mapping between a node ID and checksum hex
    func storeNode(_ nodeID: String, checksum: String) async throws

    /// Retrieve checksum hex for a given node ID
    func checksum(for nodeID: String) async throws -> String?
}

public struct CASNodeStore: CASNodeStoring {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func storeNode(_ nodeID: String, checksum: String) async throws {
        let nodesDirectory = Environment.current.stateDirectory.appending(component: "nodes")
        try await fileSystem.makeDirectory(at: nodesDirectory)

        let sanitizedNodeID = sanitizeNodeID(nodeID)
        let nodeFilePath = nodesDirectory.appending(component: sanitizedNodeID)

        try await fileSystem.writeText(checksum, at: nodeFilePath, encoding: .utf8, options: Set([.overwrite]))
    }

    public func checksum(for nodeID: String) async throws -> String? {
        let nodesDirectory = Environment.current.stateDirectory.appending(component: "nodes")
        let sanitizedNodeID = sanitizeNodeID(nodeID)
        let nodeFilePath = nodesDirectory.appending(component: sanitizedNodeID)

        guard try await fileSystem.exists(nodeFilePath) else {
            return nil
        }

        return try await fileSystem.readTextFile(at: nodeFilePath)
    }

    // MARK: - Private Methods

    private func sanitizeNodeID(_ nodeID: String) -> String {
        // Replace any characters that aren't filesystem-safe with underscores
        return nodeID.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }
}
