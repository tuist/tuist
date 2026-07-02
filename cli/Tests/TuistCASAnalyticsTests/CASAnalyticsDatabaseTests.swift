import Foundation
import Testing
import TuistEnvironment
import TuistTesting
@testable import TuistCASAnalytics

struct CASAnalyticsDatabaseTests {
    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func open_creates_database() async throws {
        let database = try CASAnalyticsDatabase()
        try database.migrate()

        try database.storeNode(key: "test-node", checksum: "abc123")
        let checksum = try database.node(for: "test-node")
        #expect(checksum == "abc123")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeCASOutput_and_retrieve() async throws {
        let database = try CASAnalyticsDatabase()
        try database.migrate()

        try database.storeCASOutput(
            key: "test-key",
            size: 1024,
            duration: 5.0,
            compressedSize: 512,
            transferDuration: 3.0,
            codecDuration: 1.5
        )
        let output = try database.casOutput(for: "test-key")
        #expect(output?.size == 1024)
        #expect(output?.duration == 5.0)
        #expect(output?.compressedSize == 512)
        #expect(output?.transferDuration == 3.0)
        #expect(output?.codecDuration == 1.5)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func storeKeyValueMetadata_and_retrieve() async throws {
        let database = try CASAnalyticsDatabase()
        try database.migrate()

        try database.storeKeyValueMetadata(key: "cache-key", operationType: "read", duration: 3.5)
        let metadata = try database.keyValueMetadata(for: "cache-key", operationType: "read")
        #expect(metadata?.duration == 3.5)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func removeOldEntries() async throws {
        let database = try CASAnalyticsDatabase()
        try database.migrate()

        try database.storeNode(key: "old-node", checksum: "old")
        try database.removeOldEntries(olderThan: Date().addingTimeInterval(1))

        let checksum = try database.node(for: "old-node")
        #expect(checksum == nil)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func buffered_writes_survive_threshold_flushes_and_reads() async throws {
        let database = try CASAnalyticsDatabase()
        try database.migrate()

        // Crosses the buffered writer's flush threshold several times: rows
        // must land through both async batch flushes and the read-triggered
        // synchronous flush.
        for index in 0 ..< 300 {
            try database.storeCASOutput(
                key: "key-\(index)",
                size: index,
                duration: 1.0,
                compressedSize: index / 2,
                transferDuration: 0.5,
                codecDuration: 0.1
            )
        }

        #expect(try database.casOutput(for: "key-0")?.size == 0)
        #expect(try database.casOutput(for: "key-150")?.size == 150)
        #expect(try database.casOutput(for: "key-299")?.size == 299)
    }
}
