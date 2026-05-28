import FileSystem
import Foundation
import Path
import Testing
@testable import XCResultParser

struct XCResultParserTests {
    let fileSystem = FileSystem()
    let parser = XCResultParser()

    /// Path to a zipped xcresult fixture. Bundles are stored zipped in the
    /// test fixtures so that individual files don't bloat PR diffs.
    private func fixtureZipPath(_ name: String) throws -> AbsolutePath {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("\(name).zip")
        return try AbsolutePath(validating: url.path)
    }

    @Test
    func parse_populatesRunDestinationsFromTheXcresultDevicesArray() async throws {
        let zipPath = try fixtureZipPath("test-with-arguments.xcresult")

        let destinations = try await fileSystem.runInTemporaryDirectory(prefix: "xcresult-parser-tests") { workDir in
            try await fileSystem.unzip(zipPath, to: workDir)
            let xcresult = workDir.appending(component: "test-with-arguments.xcresult")
            let summary = try await parser.parse(path: xcresult, rootDirectory: nil)
            return try #require(summary?.runDestinations)
        }

        #expect(destinations.count == 1)
        #expect(destinations[0].name == "iPhone Air")
        #expect(destinations[0].platform == "iOS Simulator")
        #expect(destinations[0].osVersion == "26.4")
    }

    @Test
    func parse_extractsAttachmentsUnderTheScratchDirectory() async throws {
        let zipPath = try fixtureZipPath("test-with-arguments.xcresult")

        try await fileSystem.runInTemporaryDirectory(prefix: "xcresult-parser-tests") { workDir in
            try await fileSystem.unzip(zipPath, to: workDir)
            let xcresult = workDir.appending(component: "test-with-arguments.xcresult")
            let scratch = workDir.appending(component: "scratch")
            try await fileSystem.makeDirectory(at: scratch)

            _ = try await parser.parse(path: xcresult, rootDirectory: workDir, attachmentScratchDirectory: scratch)

            // Exported attachments must live under the caller-owned scratch
            // dir so its wholesale cleanup reclaims them.
            #expect(try await fileSystem.exists(scratch.appending(component: "xcresult-attachments")))
        }
    }

    @Test
    func parse_doesNotExportAttachmentsIntoRootDirectoryWhenNoScratchGiven() async throws {
        // rootDirectory is the caller's *source* root (the user's project
        // for CLI callers) and is read-only. Without an explicit scratch
        // dir, attachments must NOT be dropped into it — they go to a temp
        // dir instead.
        let zipPath = try fixtureZipPath("test-with-arguments.xcresult")

        try await fileSystem.runInTemporaryDirectory(prefix: "xcresult-parser-tests") { workDir in
            try await fileSystem.unzip(zipPath, to: workDir)
            let xcresult = workDir.appending(component: "test-with-arguments.xcresult")
            let projectRoot = workDir.appending(component: "project")
            try await fileSystem.makeDirectory(at: projectRoot)

            _ = try await parser.parse(path: xcresult, rootDirectory: projectRoot)

            #expect(try await !fileSystem.exists(projectRoot.appending(component: "xcresult-attachments")))
        }
    }
}
