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

    @Test func readsTheServingRegionAndTreatsAMissingTableAsUnknown() async throws {
        try await FileSystem().runInTemporaryDirectory(prefix: "cas-served-by") { directory in
            let withTable = directory.appending(component: "proxy.db")
            let writer = try Connection(withTable.pathString)
            try writer.execute("""
                CREATE TABLE served_by (key TEXT, operation_type TEXT, region TEXT, created_at TEXT);
                INSERT INTO served_by VALUES ('0~action', 'read', 'us-central', '2026-09-28T09:30:00.000');
                INSERT INTO served_by VALUES ('0~empty', 'read', '', '2026-09-28T09:30:00.000');
                """)
            let served = CASMetadataReader(databasePath: withTable, legacyCASMetadataPath: nil).readServedRegions()
            #expect(served.region(key: "0~action", operationType: "read") == "us-central")
            #expect(served.region(key: "0~action", operationType: "write") == nil)
            #expect(served.region(key: "0~empty", operationType: "read") == nil)
            withExtendedLifetime(writer) {}

            let withoutTable = directory.appending(component: "swift.db")
            let legacy = try Connection(withoutTable.pathString)
            try legacy.execute("CREATE TABLE keyvalue_metadata (key TEXT, operation_type TEXT, duration REAL);")
            let legacyReader = CASMetadataReader(databasePath: withoutTable, legacyCASMetadataPath: nil)
            #expect(legacyReader.readServedRegions().regions.isEmpty)
            withExtendedLifetime(legacy) {}
        }
    }

    @Test func picksTheRegionThatAnsweredMostRequests() {
        #expect(XCActivityLogParser.dominantRegion(["us-central", "ap-southeast", "us-central"]) == "us-central")
        #expect(XCActivityLogParser.dominantRegion(["us-central", "ap-southeast"]) == "ap-southeast")
        #expect(XCActivityLogParser.dominantRegion([]) == nil)
    }
}
