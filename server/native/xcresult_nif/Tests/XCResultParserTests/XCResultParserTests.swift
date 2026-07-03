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

/// Routes the two xcresulttool reads `parse` performs (`get test-results
/// tests` and `get log --type action`) to separate canned payloads, so tests
/// can exercise an empty/absent action log independently of the test results.
private struct RoutingXCResultToolStub: CommandRunning {
    let testResultsJSON: String
    let actionLogJSON: String

    func run(
        arguments: [String],
        environment _: [String: String],
        workingDirectory _: AbsolutePath?
    ) -> AsyncThrowingStream<CommandEvent, any Error> {
        let command = arguments.last ?? ""
        let payload =
            if command.contains("get log --type action") {
                actionLogJSON
            } else if command.contains("test-results tests") {
                testResultsJSON
            } else {
                ""
            }

        return AsyncThrowingStream { continuation in
            if let redirect = command.range(of: "> '") {
                let tail = command[redirect.upperBound...]
                if let close = tail.firstIndex(of: "'") {
                    try? payload.write(toFile: String(tail[..<close]), atomically: true, encoding: .utf8)
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
    func parse_treatsAnAbsentActionLogAsEmptyInsteadOfFailing() async throws {
        // An aborted or test-less run uploads an xcresult with zero test nodes
        // and no action log: `xcresulttool get log --type action` prints "No
        // action log available" and writes nothing. Decoding that empty output
        // used to throw the opaque "The data couldn't be read because it isn't
        // in the correct format.", failing processing for the whole run. The
        // action log is auxiliary, so its absence must not abort the parse.
        let emptyTestResults = """
        {"devices": [], "testNodes": [], "testPlanConfigurations": []}
        """
        let parser = XCResultParser(
            commandRunner: RoutingXCResultToolStub(testResultsJSON: emptyTestResults, actionLogJSON: "")
        )

        let summary = try await parser.parse(path: try AbsolutePath(validating: "/tmp/empty.xcresult"), rootDirectory: nil)

        let resolved = try #require(summary)
        #expect(resolved.testModules.isEmpty)
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
              "name": "AppTests",
              "children": [
                {
                  "nodeType": "Unit test bundle",
                  "name": "AppUnitTests",
                  "children": [
                    {
                      "nodeType": "Test Suite",
                      "name": "CalculatorTests",
                      "children": [
                        {
                          "nodeType": "Test Case",
                          "name": "testUnitExample()",
                          "nodeIdentifier": "CalculatorTests/testUnitExample()",
                          "result": "Passed"
                        }
                      ]
                    }
                  ]
                },
                {
                  "nodeType": "UI test bundle",
                  "name": "AppUITests",
                  "children": [
                    {
                      "nodeType": "Test Suite",
                      "name": "OnboardingFlowTests",
                      "children": [
                        {
                          "nodeType": "Test Case",
                          "name": "testUIExample()",
                          "nodeIdentifier": "OnboardingFlowTests/testUIExample()",
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

        let statuses = try await parser.parseTestStatuses(path: try AbsolutePath(validating: "/tmp/app.xcresult"))

        let uiTest = try #require(statuses.testCases.first { $0.name == "testUIExample()" })
        #expect(uiTest.module == "AppUITests")
        let unitTest = try #require(statuses.testCases.first { $0.name == "testUnitExample()" })
        #expect(unitTest.module == "AppUnitTests")
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

    @Test
    func parse_liftsXctestRunnerErrorsOutOfTestCasesIntoErrors() async throws {
        // xctest emits a synthetic "xctest (<pid>) encountered an error" case
        // when a whole target fails to load/launch. These must not become test
        // cases (they'd inflate counts, create unbounded per-pid rows, and fire
        // webhooks). They're lifted into `errors`, keyed by target and deduped,
        // the run is marked failed, and real test cases are untouched.
        let json = """
        {
          "testNodes": [
            {
              "nodeType": "Test Plan",
              "name": "AppTests",
              "children": [
                {
                  "nodeType": "Unit test bundle",
                  "name": "AboutUserTests",
                  "children": [
                    {
                      "nodeType": "Test Case",
                      "name": "xctest (67445) encountered an error",
                      "nodeIdentifier": "xctest (67445) encountered an error",
                      "result": "Failed",
                      "children": [
                        {
                          "nodeType": "Failure Message",
                          "name": "Failed to create a bundle instance representing '.../AboutUserTests.xctest'. Check that the bundle exists on disk."
                        }
                      ]
                    },
                    {
                      "nodeType": "Test Case",
                      "name": "xctest (99999) encountered an error",
                      "nodeIdentifier": "xctest (99999) encountered an error",
                      "result": "Failed",
                      "children": [
                        {
                          "nodeType": "Failure Message",
                          "name": "Failed to create a bundle instance representing '.../AboutUserTests.xctest'. Check that the bundle exists on disk."
                        }
                      ]
                    }
                  ]
                },
                {
                  "nodeType": "Unit test bundle",
                  "name": "CalculatorTests",
                  "children": [
                    {
                      "nodeType": "Test Case",
                      "name": "testRealExample()",
                      "nodeIdentifier": "CalculatorTests/testRealExample()",
                      "result": "Passed"
                    }
                  ]
                }
              ]
            }
          ]
        }
        """
        let parser = XCResultParser(
            commandRunner: RoutingXCResultToolStub(testResultsJSON: json, actionLogJSON: "")
        )

        let summary = try #require(
            try await parser.parse(path: try AbsolutePath(validating: "/tmp/app.xcresult"), rootDirectory: nil)
        )

        // The two per-pid runner errors dedup to one, keyed by target.
        #expect(summary.errors.count == 1)
        #expect(summary.errors.first?.target == "AboutUserTests")
        #expect(summary.errors.first?.message.contains("Failed to create a bundle instance") == true)

        // They are not test cases; only the real test survives.
        let names = summary.testCases.map(\.name)
        #expect(names == ["testRealExample()"])
        #expect(!names.contains { $0.contains("encountered an error") })

        // Errors mark the run failed even though no real test failed.
        #expect(summary.status == .failed)
    }
}
