import FileSystem
import FileSystemTesting
import Foundation
import Testing

@testable import TuistCargoCommand

struct CargoCacheDetailsReportTests {
    private let action = "blake3:" + String(repeating: "a", count: 64) + ":123"
    private let object = "sha256:" + String(repeating: "b", count: 64) + ":456"

    @Test(.inTemporaryDirectory)
    func collectsOnlyPublicFieldsAndAveragesRepeatedKeyOperations() throws {
        let root = URL(fileURLWithPath: try #require(FileSystem.temporaryTestDirectory).pathString)
        try write([
            [
                "record": "task",
                "key": action,
                "name": "widgets",
                "kind": "rust",
                "status": "hit",
                "compiler_arguments": ["secret"],
                "origin": "remote",
            ],
            ["record": "timing", "key": action, "operation": "read", "duration_ns": 1_000_000],
            ["record": "timing", "key": action, "operation": "read", "duration_ns": 3_000_000],
            ["record": "reference", "key": action, "object": object],
            ["record": "adapter", "key": action, "kind": "build_script"],
            [
                "record": "cas",
                "key": object,
                "operation": "download",
                "status": "downloaded",
                "size_bytes": 456,
                "duration_ns": 1000,
            ],
        ], root: root)
        let details = try #require(CargoCacheDetailsReport.read(root: root))
        let tasks = try #require(details["tasks"] as? [[String: Any]])
        let task = try #require(tasks.first)
        #expect(tasks.count == 1)
        #expect(task["read_duration_ns"] as? UInt64 == 2_000_000)
        #expect(task["write_duration_ns"] == nil)
        #expect(task["cas_keys"] as? [String] == [object])
        #expect(task["kind"] as? String == "build_script")
        #expect(task["origin"] == nil)
        #expect(task["compiler_arguments"] == nil)
        #expect(details["truncated"] as? Bool == false)
        let json = try JSONSerialization.data(withJSONObject: details)
        #expect(!String(decoding: json, as: UTF8.self).contains("secret"))
    }

    @Test(.inTemporaryDirectory)
    func averagesLargeSamplesWithoutSaturatingTheirSum() throws {
        let root = URL(fileURLWithPath: try #require(FileSystem.temporaryTestDirectory).pathString)
        try write([
            ["record": "task", "key": action, "name": "widgets", "kind": "rust", "status": "hit"],
            ["record": "timing", "key": action, "operation": "read", "duration_ns": UInt64(9_000_000_000_000_000)],
            ["record": "timing", "key": action, "operation": "read", "duration_ns": UInt64(9_000_000_000_000_000)],
        ], root: root)
        let details = try #require(CargoCacheDetailsReport.read(root: root))
        let tasks = try #require(details["tasks"] as? [[String: Any]])
        let task = try #require(tasks.first)
        #expect(task["read_duration_ns"] as? UInt64 == 9_000_000_000_000_000)
    }

    @Test(.inTemporaryDirectory)
    func rejectsSymlinksInvalidDigestsAndIncoherentOperations() throws {
        let root = URL(fileURLWithPath: try #require(FileSystem.temporaryTestDirectory).pathString)
        try write([
            [
                "record": "cas",
                "key": object,
                "operation": "download",
                "status": "uploaded",
                "size_bytes": 456,
                "duration_ns": 1000,
            ],
            ["record": "task", "key": "not-a-digest", "name": "widgets", "kind": "rust", "status": "hit"],
            ["record": "timing", "key": action, "operation": "read", "duration_ns": -1],
        ], root: root)
        let outside = root.appendingPathComponent("outside")
        try Data("private".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("cache-details/linked.ndjson"),
            withDestinationURL: outside
        )
        let details = try #require(CargoCacheDetailsReport.read(root: root))
        #expect((details["tasks"] as? [[String: Any]])?.isEmpty == true)
        #expect((details["cas_outputs"] as? [[String: Any]])?.isEmpty == true)
        #expect(details["truncated"] as? Bool == true)
    }

    @Test(.inTemporaryDirectory)
    func boundsTasksAndDoesNotInventRemoteTransfersForLocalHits() throws {
        let root = URL(fileURLWithPath: try #require(FileSystem.temporaryTestDirectory).pathString)
        #expect(CargoCacheDetailsReport.read(root: root) == nil)
        let row: [String: Any] = ["record": "task", "key": action, "name": "widgets", "kind": "rust", "status": "hit"]
        try write(Array(repeating: row, count: 2001), root: root)
        let details = try #require(CargoCacheDetailsReport.read(root: root))
        #expect((details["tasks"] as? [[String: Any]])?.count == 2000)
        #expect((details["cas_outputs"] as? [[String: Any]])?.isEmpty == true)
        #expect(details["truncated"] as? Bool == true)
    }

    private func write(_ rows: [[String: Any]], root: URL) throws {
        let directory = root.appendingPathComponent("cache-details")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var data = Data()
        for row in rows {
            data.append(try JSONSerialization.data(withJSONObject: row))
            data.append(contentsOf: [UInt8(0x0A)])
        }
        try data.write(to: directory.appendingPathComponent("1.ndjson"))
    }
}
