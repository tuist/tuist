import Foundation
import Testing
import TuistEnvironment
import TuistTesting
@testable import TuistCASAnalytics

struct CASNodeStoreTests {
    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeNode_and_checksum() async throws {
        let mockEnvironment = try #require(Environment.mocked)
        let database = try CASAnalyticsDatabase.open()
        try database.migrate()
        let subject = CASNodeStore(database: database)

        try await subject.storeNode("test-node", checksum: "abc123")
        let result = try await subject.checksum(for: "test-node")
        #expect(result == "abc123")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func checksum_when_not_stored() async throws {
        let mockEnvironment = try #require(Environment.mocked)
        let database = try CASAnalyticsDatabase.open()
        try database.migrate()
        let subject = CASNodeStore(database: database)

        let result = try await subject.checksum(for: "non-existing")
        #expect(result == nil)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeNode_sanitizes_special_characters() async throws {
        let mockEnvironment = try #require(Environment.mocked)
        let database = try CASAnalyticsDatabase.open()
        try database.migrate()
        let subject = CASNodeStore(database: database)

        try await subject.storeNode("node/with:special/chars", checksum: "sanitized123")
        let result = try await subject.checksum(for: "node/with:special/chars")
        #expect(result == "sanitized123")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeNode_overwrites_existing() async throws {
        let mockEnvironment = try #require(Environment.mocked)
        let database = try CASAnalyticsDatabase.open()
        try database.migrate()
        let subject = CASNodeStore(database: database)

        try await subject.storeNode("node1", checksum: "original")
        try await subject.storeNode("node1", checksum: "updated")
        let result = try await subject.checksum(for: "node1")
        #expect(result == "updated")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func multiple_nodes() async throws {
        let mockEnvironment = try #require(Environment.mocked)
        let database = try CASAnalyticsDatabase.open()
        try database.migrate()
        let subject = CASNodeStore(database: database)

        let nodes = [("node1", "checksum1"), ("node2", "checksum2"), ("node/3", "checksum3")]
        for (id, checksum) in nodes {
            try await subject.storeNode(id, checksum: checksum)
        }
        for (id, expected) in nodes {
            #expect(try await subject.checksum(for: id) == expected)
        }
    }
}
