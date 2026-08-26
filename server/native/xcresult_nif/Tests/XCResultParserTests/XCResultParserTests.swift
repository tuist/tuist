import Command
import FileSystem
import Foundation
import os
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

/// Records the shell payload of every command the parser issues.
private struct RecordingXCResultToolStub: CommandRunning {
    let testResultsJSON: String
    let commands = OSAllocatedUnfairLock<[String]>(initialState: [])

    func run(
        arguments: [String],
        environment _: [String: String],
        workingDirectory _: AbsolutePath?
    ) -> AsyncThrowingStream<CommandEvent, any Error> {
        let command = arguments.last ?? ""
        commands.withLock { $0.append(command) }
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
    func parse_reportsAnEmptyTestResultsOutputAsItsOwnFailure() async throws {
        // `xcresulttool get test-results tests` exits cleanly having written
        // nothing for some bundles. Zero bytes decode as "dataCorrupted [...]
        // The given data was not valid JSON", which reads as a malformed
        // payload; absent output is its own failure, distinct from output we
        // cannot decode.
        let parser = XCResultParser(commandRunner: XCResultToolStub(testResultsJSON: ""))
        let path = try AbsolutePath(validating: "/tmp/empty.xcresult")

        await #expect(throws: XCResultParserError.emptyOutput(step: "test-results", path: path)) {
            try await parser.parse(path: path, rootDirectory: nil)
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

    @Test
    func parse_liftsRunnerErrorsRegardlessOfPrefix_andKeepsRealTestsNamedSimilarly() async throws {
        // The runner-process name is only "xctest" for unit tests. For UI tests
        // it's the app/UI-runner target (varies per project), it sometimes has no
        // pid, and Xcode also emits a generic "The test runner encountered an
        // error". All are lifted structurally (nodeIdentifier == name plus a
        // Failure Message child), regardless of the prefix. A real test whose
        // display name merely ends this way, but which carries a real
        // "Suite/method" identifier, must survive as a test case.
        let json = """
        {
          "testNodes": [
            {
              "nodeType": "Test Plan",
              "name": "AppTests",
              "children": [
                {
                  "nodeType": "UI test bundle",
                  "name": "AppUITests",
                  "children": [
                    {
                      "nodeType": "Test Case",
                      "name": "UITestTarget (4242) encountered an error",
                      "nodeIdentifier": "UITestTarget (4242) encountered an error",
                      "result": "Failed",
                      "children": [
                        { "nodeType": "Failure Message", "name": "AppUITests-Runner failed to launch." }
                      ]
                    },
                    {
                      "nodeType": "Test Case",
                      "name": "EMAUITests-Runner (99) encountered an error",
                      "nodeIdentifier": "EMAUITests-Runner (99) encountered an error",
                      "result": "Failed",
                      "children": [
                        { "nodeType": "Failure Message", "name": "The UI test runner failed to launch." }
                      ]
                    }
                  ]
                },
                {
                  "nodeType": "Unit test bundle",
                  "name": "SnapshotTests",
                  "children": [
                    {
                      "nodeType": "Test Case",
                      "name": "SnapshotTestHost encountered an error",
                      "nodeIdentifier": "SnapshotTestHost encountered an error",
                      "result": "Failed",
                      "children": [
                        { "nodeType": "Failure Message", "name": "Failed to create a bundle instance." }
                      ]
                    },
                    {
                      "nodeType": "Test Case",
                      "name": "The test runner encountered an error",
                      "nodeIdentifier": "The test runner encountered an error",
                      "result": "Failed",
                      "children": [
                        { "nodeType": "Failure Message", "name": "The test runner encountered an error." }
                      ]
                    }
                  ]
                },
                {
                  "nodeType": "Unit test bundle",
                  "name": "RealTests",
                  "children": [
                    {
                      "nodeType": "Test Case",
                      "name": "the server encountered an error",
                      "nodeIdentifier": "RealTests/theServerErrorIsSurfaced()",
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

        // All four runner errors are lifted — an app/UI-runner target, an exotic
        // single-token prefix, a no-pid form, and Xcode's generic string — keyed
        // by their bundle target.
        let lifted = Set(summary.errors.map { "\($0.target ?? "")|\($0.message)" })
        #expect(lifted == [
            "AppUITests|AppUITests-Runner failed to launch.",
            "AppUITests|The UI test runner failed to launch.",
            "SnapshotTests|Failed to create a bundle instance.",
            "SnapshotTests|The test runner encountered an error.",
        ])

        // The real test whose display name ends the same way, but which has a
        // real "Suite/method" identifier, is kept and no runner error leaked in.
        #expect(summary.testCases.map(\.name) == ["the server encountered an error"])

        #expect(summary.status == .failed)
    }

    @Test
    func parse_liftsUnattributedSwiftTestingIssuesIntoErrorsWithoutFailingTheRun() async throws {
        // Swift Testing issues recorded when no test is running (a leaked task,
        // a callback that outlives its test) land in a synthetic
        // "Issues recorded without an associated test or suite" case. xcodebuild
        // gates on tests and this belongs to none, so it exits 0; the node must
        // not become a test case nor drag the run red, or the dashboard shows a
        // failed run for a green CI job. The issues are kept as target-keyed
        // errors, deduped across the repetitions that re-record them.
        let json = """
        {
          "testNodes": [
            {
              "nodeType": "Test Plan",
              "name": "UnitTestSuite",
              "children": [
                {
                  "nodeType": "Unit test bundle",
                  "name": "ChatTests",
                  "children": [
                    {
                      "nodeType": "Test Case",
                      "name": "Issues recorded without an associated test or suite",
                      "result": "Failed",
                      "children": [
                        {
                          "nodeType": "Failure Message",
                          "name": "ChatTests.swift:107: response.0.contains { $0.numberOfNewMessages == 0 }"
                        },
                        {
                          "nodeType": "Failure Message",
                          "name": "ChatTests.swift:107: response.0.contains { $0.numberOfNewMessages == 0 }"
                        },
                        {
                          "nodeType": "Failure Message",
                          "name": "ChatTests.swift:153: response.0.contains { $0.numberOfNewMessages == 1 }"
                        }
                      ]
                    },
                    {
                      "nodeType": "Test Case",
                      "name": "sendsMessage()",
                      "nodeIdentifier": "ChatTests/sendsMessage()",
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

        let lifted = Set(summary.errors.map { "\($0.target ?? "")|\($0.message)" })
        #expect(lifted == [
            "ChatTests|Issue recorded without an associated test: ChatTests.swift:107: response.0.contains { $0.numberOfNewMessages == 0 }",
            "ChatTests|Issue recorded without an associated test: ChatTests.swift:153: response.0.contains { $0.numberOfNewMessages == 1 }",
        ])

        #expect(summary.testCases.map(\.name) == ["sendsMessage()"])

        // Unlike a runner error, these do not fail the run: xcodebuild exited 0.
        #expect(summary.status == .passed)
    }

    @Test
    func parse_keepsRealTestNamedLikeTheUnattributedIssuesNode() async throws {
        // A real Swift Testing case can be displayed with that exact name; it
        // carries a "Suite/method" identifier, so it stays a test case and still
        // fails the run.
        let json = """
        {
          "testNodes": [
            {
              "nodeType": "Test Plan",
              "name": "UnitTestSuite",
              "children": [
                {
                  "nodeType": "Unit test bundle",
                  "name": "ReporterTests",
                  "children": [
                    {
                      "nodeType": "Test Case",
                      "name": "Issues recorded without an associated test or suite",
                      "nodeIdentifier": "ReporterTests/issuesRecordedWithoutATest()",
                      "result": "Failed",
                      "children": [
                        { "nodeType": "Failure Message", "name": "Reporter.swift:12: Expectation failed" }
                      ]
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

        #expect(summary.errors.isEmpty)
        #expect(summary.testCases.map(\.name) == ["Issues recorded without an associated test or suite"])
        #expect(summary.status == .failed)
    }

    /// The parser shells out through `/bin/sh -c`. Without `exec` the shell
    /// forks the tool and waits, so `Process.terminate()` on cancellation
    /// signals the shell only and the tool keeps running, reparented, holding
    /// its process-limiter permit and writing into a temp directory the caller
    /// is about to delete.
    @Test
    func shellCommandsExecTheToolSoTheyStayCancellable() async throws {
        let runner = RecordingXCResultToolStub(testResultsJSON: "{}")
        let parser = XCResultParser(commandRunner: runner)

        _ = try? await parser.parse(path: try AbsolutePath(validating: "/tmp/app.xcresult"), rootDirectory: nil)

        let commands = runner.commands.withLock { $0 }
        #expect(!commands.isEmpty)
        for command in commands where command.contains("xcresulttool") {
            #expect(command.hasPrefix("exec "), "not cancellable, shell would fork and wait: \(command)")
        }
    }

    /// Guards the mechanism itself rather than the spelling: cancelling the
    /// task must leave no descendant behind.
    @Test
    func cancellingACommandTerminatesItsRealChildProcess() async throws {
        // Unique enough to identify this test's process in the table.
        let marker = "774411"
        defer { _ = runToCompletion("/usr/bin/pkill", ["-f", "sleep \(marker)"]) }

        let task = Task {
            for try await _ in CommandRunner().run(arguments: ["/bin/sh", "-c", "exec /bin/sleep \(marker)"]) {}
        }

        try await waitFor("the child to start") { processExists(marker) }
        task.cancel()
        try await waitFor("the child to be terminated") { !processExists(marker) }
    }
}

private func runToCompletion(_ executable: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return -1
    }
    process.waitUntilExit()
    return process.terminationStatus
}

private func processExists(_ marker: String) -> Bool {
    runToCompletion("/usr/bin/pgrep", ["-f", "sleep \(marker)"]) == 0
}

/// Polls rather than sleeping a fixed interval, so the test is neither slow
/// when the transition is fast nor flaky when the machine is loaded.
private func waitFor(_ description: String, _ condition: @Sendable () -> Bool) async throws {
    for _ in 0 ..< 100 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(100))
    }
    Issue.record("Timed out waiting for \(description)")
}
