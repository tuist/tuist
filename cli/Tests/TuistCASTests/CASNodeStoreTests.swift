import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistSupport
import TuistTesting
@testable import TuistCASAnalytics

struct CASNodeStoreTests {
    private let fileSystem = FileSystem()
    private let subject = CASNodeStore()

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeNode_and_checksum_integration() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)

        let nodeID = "integration-node"
        let checksum = "integration123abc"

        // When
        try await subject.storeNode(nodeID, checksum: checksum)
        let retrievedChecksum = try await subject.checksum(for: nodeID)

        // Then
        #expect(retrievedChecksum == checksum)

        // Verify the file was actually created
        let nodesDirectory = mockEnvironment.stateDirectory.appending(component: "nodes")
        let nodeFilePath = nodesDirectory.appending(component: "integration-node")
        let fileExists = try await fileSystem.exists(nodeFilePath)
        #expect(fileExists)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeNode_creates_nodes_directory_when_missing() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)

        let nodeID = "test-node-id"
        let checksum = "abc123def456"
        let nodesDirectory = mockEnvironment.stateDirectory.appending(component: "nodes")

        // Verify nodes directory doesn't exist initially
        let initialExists = try await fileSystem.exists(nodesDirectory)
        #expect(!initialExists)

        // When
        try await subject.storeNode(nodeID, checksum: checksum)

        // Then
        let directoryExists = try await fileSystem.exists(nodesDirectory)
        #expect(directoryExists)

        let nodeFilePath = nodesDirectory.appending(component: "test-node-id")
        let fileExists = try await fileSystem.exists(nodeFilePath)
        #expect(fileExists)

        let storedChecksum = try await fileSystem.readTextFile(at: nodeFilePath)
        #expect(storedChecksum == checksum)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeNode_with_sanitized_node_id() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)

        let fileSystem = FileSystem()
        let subject = CASNodeStore(fileSystem: fileSystem)
        let nodeID = "node/with:special/characters"
        let checksum = "sanitized123"

        // When
        try await subject.storeNode(nodeID, checksum: checksum)

        // Then
        let nodesDirectory = mockEnvironment.stateDirectory.appending(component: "nodes")
        let sanitizedNodeFilePath = nodesDirectory.appending(component: "node_with_special_characters")
        let fileExists = try await fileSystem.exists(sanitizedNodeFilePath)
        #expect(fileExists)

        let storedChecksum = try await fileSystem.readTextFile(at: sanitizedNodeFilePath)
        #expect(storedChecksum == checksum)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func checksum_when_node_file_does_not_exist() async throws {
        // Given
        let subject = CASNodeStore()
        let nodeID = "non-existing-node"

        // When
        let result = try await subject.checksum(for: nodeID)

        // Then
        #expect(result == nil)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func checksum_with_sanitized_node_id() async throws {
        // Given
        let nodeID = "node/with:special/chars"
        let expectedChecksum = "sanitized789"

        // First store the node
        try await subject.storeNode(nodeID, checksum: expectedChecksum)

        // When
        let result = try await subject.checksum(for: nodeID)

        // Then
        #expect(result == expectedChecksum)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeNode_with_empty_checksum() async throws {
        // Given
        let nodeID = "empty-checksum-node"
        let emptyChecksum = ""

        // When
        try await subject.storeNode(nodeID, checksum: emptyChecksum)

        // Then
        let retrievedChecksum = try await subject.checksum(for: nodeID)
        #expect(retrievedChecksum == emptyChecksum)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeNode_overwrites_existing_checksum() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)

        let nodeID = "overwrite-node"
        let originalChecksum = "original123"
        let newChecksum = "updated456"

        // When - Store original checksum
        try await subject.storeNode(nodeID, checksum: originalChecksum)
        let firstChecksum = try await subject.checksum(for: nodeID)
        #expect(firstChecksum == originalChecksum)

        // When - Store new checksum for same node ID using overwrite approach
        let nodesDirectory = mockEnvironment.stateDirectory.appending(component: "nodes")
        let nodeFilePath = nodesDirectory.appending(component: "overwrite-node")

        // Use the FileSystem writeText with overwrite option (like in acceptance tests)
        try await fileSystem.writeText(newChecksum, at: nodeFilePath, options: Set([.overwrite]))

        let updatedChecksum = try await subject.checksum(for: nodeID)

        // Then - Verify the checksum was updated
        #expect(updatedChecksum == newChecksum)
        #expect(updatedChecksum != originalChecksum)

        // Verify the file exists with the new content
        let fileExists = try await fileSystem.exists(nodeFilePath)
        #expect(fileExists)

        let storedContent = try await fileSystem.readTextFile(at: nodeFilePath)
        #expect(storedContent == newChecksum)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func sanitizeNodeID_replaces_filesystem_unsafe_characters() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        let unsafeNodeID = "node/with:many/unsafe:characters/and:more"
        let checksum = "sanitization123"

        // When
        try await subject.storeNode(unsafeNodeID, checksum: checksum)

        // Then
        let nodesDirectory = mockEnvironment.stateDirectory.appending(component: "nodes")
        let safeNodeFilePath = nodesDirectory.appending(component: "node_with_many_unsafe_characters_and_more")
        let fileExists = try await fileSystem.exists(safeNodeFilePath)
        #expect(fileExists)

        let storedChecksum = try await fileSystem.readTextFile(at: safeNodeFilePath)
        #expect(storedChecksum == checksum)

        // Verify we can retrieve it using the original unsafe ID
        let retrievedChecksum = try await subject.checksum(for: unsafeNodeID)
        #expect(retrievedChecksum == checksum)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func multiple_nodes_can_be_stored_and_retrieved() async throws {
        // Given

        let nodes = [
            ("node1", "checksum1"),
            ("node2", "checksum2"),
            ("node/3", "checksum3"),
            ("node:4", "checksum4"),
        ]

        // When
        for (nodeID, checksum) in nodes {
            try await subject.storeNode(nodeID, checksum: checksum)
        }

        // Then
        for (nodeID, expectedChecksum) in nodes {
            let retrievedChecksum = try await subject.checksum(for: nodeID)
            #expect(retrievedChecksum == expectedChecksum)
        }
    }
}
