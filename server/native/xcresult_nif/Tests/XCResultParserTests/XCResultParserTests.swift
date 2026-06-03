import Command
import FileSystem
import Foundation
import Path
import Testing
@testable import XCResultParser

/// Stands in for `xcresulttool`. `loadTestOutput` shells out with a redirect to
/// a temp file and reads it back, so the stub writes the canned test-results
/// JSON to that redirect target — the real decoding and node classification then
/// run unchanged through the public parsing API.
private struct XCResultToolStub: CommandRunning {
    let testResultsJSON: String

    func run(
        arguments: [String],
        environment _: [String: String],
        workingDirectory _: AbsolutePath?
    ) -> AsyncThrowingStream<CommandEvent, any Error> {
        let command = arguments.last ?? ""
        return AsyncThrowingStream { continuation in
            if let redirect = command.range(of: "> '") {
                let tail = command[redirect.upperBound...]
                if let close = tail.firstIndex(of: "'") {
                    try? testResultsJSON.write(toFile: String(tail[..<close]), atomically: true, encoding: .utf8)
                }
            }
            continuation.finish()
        }
    }
}

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
    func parse_extractsAttachmentsUnderTheAttachmentsDirectory() async throws {
        let zipPath = try fixtureZipPath("test-with-arguments.xcresult")

        try await fileSystem.runInTemporaryDirectory(prefix: "xcresult-parser-tests") { workDir in
            try await fileSystem.unzip(zipPath, to: workDir)
            let xcresult = workDir.appending(component: "test-with-arguments.xcresult")
            let attachmentsDirectory = workDir.appending(component: "attachments")
            try await fileSystem.makeDirectory(at: attachmentsDirectory)

            _ = try await parser.parse(path: xcresult, rootDirectory: workDir, attachmentsDirectory: attachmentsDirectory)

            // Exported attachments must live under the caller-owned
            // attachments dir so its wholesale cleanup reclaims them.
            #expect(try await fileSystem.exists(attachmentsDirectory.appending(component: "xcresult-attachments")))
        }
    }

    @Test
    func parseTestStatuses_derivesModuleNameForUITestBundlesNotJustUnitTestBundles() async throws {
        // xcresulttool reports unit test bundles as "Unit test bundle" and UI
        // test bundles as "UI test bundle". When the module isn't derived, the
        // server stores it as "Unknown", which breaks quarantine `-skip-testing`
        // matching so the test keeps running. Both bundle kinds must resolve to
        // their bundle name.
        let json = """
        {
          "testNodes": [
            {
              "nodeType": "Test Plan",
              "name": "DepopTests",
              "children": [
                {
                  "nodeType": "Unit test bundle",
                  "name": "DepopUnitTests",
                  "children": [
                    {
                      "nodeType": "Test Suite",
                      "name": "ProductDetailsTests",
                      "children": [
                        {
                          "nodeType": "Test Case",
                          "name": "testUnitExample()",
                          "nodeIdentifier": "ProductDetailsTests/testUnitExample()",
                          "result": "Passed"
                        }
                      ]
                    }
                  ]
                },
                {
                  "nodeType": "UI test bundle",
                  "name": "DepopUITests",
                  "children": [
                    {
                      "nodeType": "Test Suite",
                      "name": "BuyerMakeOfferFlowFunctionalTests",
                      "children": [
                        {
                          "nodeType": "Test Case",
                          "name": "testMakeOfferOnProductWithoutSize()",
                          "nodeIdentifier": "BuyerMakeOfferFlowFunctionalTests/testMakeOfferOnProductWithoutSize()",
                          "result": "Passed"
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
        """
        let parser = XCResultParser(commandRunner: XCResultToolStub(testResultsJSON: json))

        let statuses = try await parser.parseTestStatuses(path: try AbsolutePath(validating: "/tmp/depop.xcresult"))

        let uiTest = try #require(statuses.testCases.first { $0.name == "testMakeOfferOnProductWithoutSize()" })
        #expect(uiTest.module == "DepopUITests")
        let unitTest = try #require(statuses.testCases.first { $0.name == "testUnitExample()" })
        #expect(unitTest.module == "DepopUnitTests")
    }

    @Test
    func parse_doesNotExportAttachmentsIntoRootDirectoryWhenNoAttachmentsDirectoryGiven() async throws {
        // rootDirectory is the caller's *source* root (the user's project
        // for CLI callers) and is read-only. Without an explicit
        // attachments directory, attachments must NOT be dropped into it —
        // they go to a temp dir instead.
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
