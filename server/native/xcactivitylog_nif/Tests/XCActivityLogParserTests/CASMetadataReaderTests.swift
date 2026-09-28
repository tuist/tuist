import CASAnalyticsDatabase
import FileSystem
import Foundation
import Testing

@testable import XCActivityLogParser

struct CASMetadataReaderTests {
    @Test(arguments: ["WAL", "DELETE"])
    func readsCheckpointedArchiveWithoutSidecars(journalMode: String) async throws {
        try await FileSystem().runInTemporaryDirectory(prefix: "cas-metadata") { directory in
            let source = directory.appending(component: "source.db")
            let snapshot = directory.appending(component: "archive ? #.db")
            let writer = try Connection(source.pathString)
            try writer.execute("PRAGMA journal_mode = \(journalMode)")
            try writer.execute("""
                CREATE TABLE nodes (key TEXT PRIMARY KEY, checksum TEXT);
                CREATE TABLE cas_outputs (key TEXT PRIMARY KEY, size INTEGER, compressed_size INTEGER, duration REAL);
                CREATE TABLE keyvalue_metadata (key TEXT, operation_type TEXT, duration REAL);
                INSERT INTO nodes VALUES ('0~output', 'CHECKSUM');
                INSERT INTO cas_outputs VALUES ('CHECKSUM', 100, 40, 3.5);
                INSERT INTO keyvalue_metadata VALUES ('0~action', 'read', 2.5);
                PRAGMA wal_checkpoint(TRUNCATE);
                """)
            try FileManager.default.copyItem(atPath: source.pathString, toPath: snapshot.pathString)
            let reader = CASMetadataReader(databasePath: snapshot, legacyCASMetadataPath: nil)

            #expect(await reader.readChecksum(nodeID: "0~output") == "CHECKSUM")
            let output = try #require(await reader.readOutputMetadata(checksum: "CHECKSUM"))
            #expect(output.size == 100)
            #expect(output.compressedSize == 40)
            #expect(output.duration == 3.5)
            #expect(await reader.readKeyValueMetadata(key: "0~action", operationType: "read")?.duration == 2.5)
            #expect(!FileManager.default.fileExists(atPath: snapshot.pathString + "-wal"))
            #expect(!FileManager.default.fileExists(atPath: snapshot.pathString + "-shm"))
            withExtendedLifetime(writer) {}
        }
    }

    @Test func readsWhoAnsweredAndTreatsAMissingTableAsUnknown() async throws {
        try await FileSystem().runInTemporaryDirectory(prefix: "cas-served-by") { directory in
            let withTable = directory.appending(component: "proxy.db")
            let writer = try Connection(withTable.pathString)
            try writer.execute("""
                CREATE TABLE served_by (key TEXT, operation_type TEXT, region TEXT, node TEXT, connected_at TEXT, created_at TEXT);
                INSERT INTO served_by VALUES ('0~action', 'read', 'us-central', 'acme-us-central-0', '2026-09-28T09:00:00.000', '2026-09-28T09:30:00.000');
                INSERT INTO served_by VALUES ('0~empty', 'read', '', '', '', '2026-09-28T09:30:00.000');
                """)
            let reader = CASMetadataReader(databasePath: withTable, legacyCASMetadataPath: nil)
            #expect(await reader.readServedBy(key: "0~action", operationType: "read") == ServedByEntry(
                region: "us-central", node: "acme-us-central-0", connectedAt: "2026-09-28T09:00:00.000"
            ))
            #expect(await reader.readServedBy(key: "0~action", operationType: "write") == nil)
            #expect(await reader.readServedBy(key: "0~empty", operationType: "read") == nil)
            withExtendedLifetime(writer) {}

            let withoutTable = directory.appending(component: "swift.db")
            let legacy = try Connection(withoutTable.pathString)
            try legacy.execute("CREATE TABLE keyvalue_metadata (key TEXT, operation_type TEXT, duration REAL);")
            let legacyReader = CASMetadataReader(databasePath: withoutTable, legacyCASMetadataPath: nil)
            #expect(await legacyReader.readServedBy(key: "0~action", operationType: "read") == nil)
            withExtendedLifetime(legacy) {}
        }
    }

    @Test func summarizesTheRegionThatAnsweredMostRequests() {
        let entries = [
            ServedByEntry(region: "us-central", node: "a-0", connectedAt: "2026-09-28T09:10:00.000"),
            ServedByEntry(region: "us-central", node: "a-1", connectedAt: "2026-09-28T09:00:00.000"),
            ServedByEntry(region: "us-central", node: "a-1", connectedAt: ""),
            ServedByEntry(region: "ap-southeast", node: "b-0", connectedAt: "2026-09-28T08:00:00.000"),
        ]
        // 2026-09-28T09:15:00Z, a quarter of an hour after that connection opened.
        let buildStartedAt = 1_790_586_900.0
        #expect(CacheServing.summarize(entries, buildStartedAt: buildStartedAt) == CacheServing(
            region: "us-central",
            node: "a-1",
            connected_at: "2026-09-28T09:00:00.000",
            connected_before_build_seconds: 900,
            region_requests: 3,
            observed_requests: 4
        ))
        #expect(CacheServing.summarize(entries, buildStartedAt: 1_790_586_000.0)?.connected_before_build_seconds == 0,
                "a connection opened during the build is not older than it")
        #expect(CacheServing.summarize(entries)?.connected_before_build_seconds == nil)
        #expect(CacheServing.summarize([]) == nil)
        #expect(CacheServing.summarize([
            ServedByEntry(region: "eu-west", node: "", connectedAt: ""),
        ])?.connected_at == nil)
    }
}
