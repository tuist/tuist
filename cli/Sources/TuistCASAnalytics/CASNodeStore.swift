import FileSystem
import Foundation
import Path
import TuistSupport

public final class CASNodeStore: CASNodeMappingStoring {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func storeNode(_ nodeID: String, checksum: String) async throws {
        let nodesDirectory = Environment.current.stateDirectory.appending(component: "nodes")
        try await ensureNodesDirectoryExists(nodesDirectory)

        let sanitizedNodeID = sanitizeNodeID(nodeID)
        let nodeFilePath = nodesDirectory.appending(component: sanitizedNodeID)

        try await fileSystem.writeText(checksum, at: nodeFilePath)
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

    private func ensureNodesDirectoryExists(_ nodesDirectory: AbsolutePath) async throws {
        if try await !fileSystem.exists(nodesDirectory) {
            try await fileSystem.makeDirectory(at: nodesDirectory)
        }
    }

    private func sanitizeNodeID(_ nodeID: String) -> String {
        // Replace any characters that aren't filesystem-safe with underscores
        return nodeID.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }
}
