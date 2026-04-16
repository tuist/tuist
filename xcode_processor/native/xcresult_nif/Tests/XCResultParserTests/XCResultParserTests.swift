import Foundation
import Path
import Testing
@testable import XCResultParser

struct XCResultParserTests {
    let parser = XCResultParser()

    /// Unzips an xcresult fixture into a fresh temporary directory and returns
    /// the path to the unzipped `.xcresult` bundle. The bundles are stored
    /// zipped in the test fixtures so individual files don't bloat PR diffs.
    private func unzipFixture(_ name: String) throws -> (xcresult: AbsolutePath, cleanup: () -> Void) {
        let zipURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("\(name).zip")

        let workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xcresult-parser-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", zipURL.path, "-d", workDir.path]
        try process.run()
        process.waitUntilExit()

        let xcresultURL = workDir.appendingPathComponent(name)
        let path = try AbsolutePath(validating: xcresultURL.path)
        return (path, { try? FileManager.default.removeItem(at: workDir) })
    }

    @Test
    func parse_populatesRunDestinationsFromTheXcresultDevicesArray() async throws {
        let (xcresult, cleanup) = try unzipFixture("test-with-arguments.xcresult")
        defer { cleanup() }

        let summary = try await parser.parse(path: xcresult, rootDirectory: nil)
        let destinations = try #require(summary?.runDestinations)

        #expect(destinations.count == 1)
        #expect(destinations[0].name == "iPhone Air")
        #expect(destinations[0].platform == "iOS Simulator")
        #expect(destinations[0].osVersion == "26.4")
    }
}
