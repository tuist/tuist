import FileSystem
import FileSystemTesting
import Foundation
import Testing

@testable import TuistCargoCommand

struct CargoCacheReportTests {
    @Test(.inTemporaryDirectory)
    func sumsOnlyVersionedBoundedMeasurements() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let root = URL(fileURLWithPath: directory.pathString)
        let reports = root.appendingPathComponent("cache-reports")
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        var payload: [String: Any] = Dictionary(uniqueKeysWithValues: CargoCacheReport.counters.map { ($0, 0 as Any) })
        payload["version"] = 5
        payload["hits"] = 12
        payload["downloaded_bytes"] = 42
        payload["compiler_arguments"] = ["must not be collected"]
        for index in 0 ..< 2 {
            try JSONSerialization.data(withJSONObject: payload).write(to: reports.appendingPathComponent("\(index).json"))
        }
        payload["version"] = 999
        try JSONSerialization.data(withJSONObject: payload).write(to: reports.appendingPathComponent("future.json"))
        let metrics = try #require(CargoCacheReport.read(root: root))
        #expect(metrics["hits"] as? UInt64 == 24)
        #expect(metrics["downloaded_bytes"] as? UInt64 == 84)
        #expect(metrics["version"] as? Int == 1)
        #expect(metrics["compiler_arguments"] == nil)
    }

    @Test(.inTemporaryDirectory)
    func saturatesOverflowingCounters() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let root = URL(fileURLWithPath: directory.pathString)
        let reports = root.appendingPathComponent("cache-reports")
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        var payload: [String: Any] = Dictionary(uniqueKeysWithValues: CargoCacheReport.counters.map { ($0, 0 as Any) })
        payload["version"] = 5
        payload["hits"] = UInt64.max
        for index in 0 ..< 2 {
            try JSONSerialization.data(withJSONObject: payload).write(to: reports.appendingPathComponent("\(index).json"))
        }
        let metrics = try #require(CargoCacheReport.read(root: root))
        #expect(metrics["hits"] as? UInt64 == 9_000_000_000_000_000)
    }

    @Test(.inTemporaryDirectory)
    func limitsAggregateBytesAndRejectsSymlinks() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let root = URL(fileURLWithPath: directory.pathString)
        let reports = root.appendingPathComponent("cache-reports")
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        var payload: [String: Any] = Dictionary(uniqueKeysWithValues: CargoCacheReport.counters.map { ($0, 0 as Any) })
        payload["version"] = 5
        payload["hits"] = 1
        let json = try JSONSerialization.data(withJSONObject: payload)
        let padded = json + Data(repeating: 0x20, count: 400_000 - json.count)
        for index in 0 ..< 22 {
            try padded.write(to: reports.appendingPathComponent("\(index).json"))
        }
        let metrics = try #require(CargoCacheReport.read(root: root))
        #expect(metrics["hits"] as? UInt64 == 20)
        try FileManager.default.removeItem(at: reports)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("outside.json")
        try json.write(to: outside)
        try FileManager.default.createSymbolicLink(at: reports.appendingPathComponent("linked.json"), withDestinationURL: outside)
        try (json + Data(repeating: 0x20, count: 512_001)).write(to: reports.appendingPathComponent("large.json"))
        #expect(CargoCacheReport.read(root: root) == nil)
    }

    @Test(.inTemporaryDirectory)
    func doesNotInventMetricsForMissingOrInvalidReports() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let root = URL(fileURLWithPath: directory.pathString)
        #expect(CargoCacheReport.read(root: root) == nil)
        let reports = root.appendingPathComponent("cache-reports")
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        try Data("{\"version\":5,\"hits\":-1}".utf8).write(to: reports.appendingPathComponent("invalid.json"))
        #expect(CargoCacheReport.read(root: root) == nil)
    }
}
