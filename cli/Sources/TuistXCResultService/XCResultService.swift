import Command
import FileSystem
import Foundation
import Mockable
import Path
import TuistSupport

@Mockable
public protocol XCResultServicing {
    func parse(path: AbsolutePath, rootDirectory: AbsolutePath?) async throws -> TestSummary?
    func mostRecentXCResultFile(projectDerivedDataDirectory: AbsolutePath) async throws -> XCResultFile?
}

public struct XCResultFile {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

struct XCLogStoreManifestPlist: Decodable {
    let logs: [String: Log]

    struct Log: Decodable {
        let fileName: String
        let timeStoppedRecording: Double
    }
}

// swiftlint:disable:next type_body_length
public struct XCResultService: XCResultServicing {
    private let fileSystem: FileSysteming
    private let commandRunner: CommandRunning

    public init(
        fileSystem: FileSysteming = FileSystem(),
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
    }

    /// Convert seconds to milliseconds, ensuring non-zero values are at least 1ms
    private func secondsToMilliseconds(_ seconds: Double) -> Int {
        let ms = Int(seconds * 1000)
        // If the original value was non-zero but rounds to 0ms, use 1ms
        return (ms == 0 && seconds > 0) ? 1 : ms
    }

    public func mostRecentXCResultFile(projectDerivedDataDirectory: AbsolutePath)
        async throws -> XCResultFile?
    {
        let logsBuildDirectoryPath = projectDerivedDataDirectory.appending(
            components: "Logs", "Test"
        )
        let logManifestPlistPath = logsBuildDirectoryPath.appending(
            components: "LogStoreManifest.plist"
        )
        guard try await fileSystem.exists(logManifestPlistPath) else { return nil }
        let plist: XCLogStoreManifestPlist = try await fileSystem.readPlistFile(
            at: logManifestPlistPath
        )

        guard let latestLog = plist.logs.values.sorted(by: {
            $0.timeStoppedRecording > $1.timeStoppedRecording
        }).first
        else {
            return nil
        }

        return XCResultFile(url: logsBuildDirectoryPath.appending(component: latestLog.fileName).url)
    }

    public func parse(path: AbsolutePath, rootDirectory: AbsolutePath?) async throws -> TestSummary? {
        let now = Date()

        // Run xcresulttool to get test results as JSON
        let outputString = try await commandRunner.run(
            arguments: [
                "/usr/bin/xcrun", "xcresulttool",
                "get", "test-results", "tests",
                "--path", path.pathString,
            ]
        ).concatenatedString()

        guard let outputData = outputString.data(using: .utf8) else {
            throw NSError(domain: "XCResultService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert output to data"])
        }

        let testOutput = try JSONDecoder().decode(XCResultTestOutput.self, from: outputData)

        let testSummary = await parseTestOutput(testOutput, rootDirectory: rootDirectory, xcresultPath: path)

        print("Total parsing time: ", Date().timeIntervalSince1970 - now.timeIntervalSince1970)
        return testSummary
    }

    private func parseTestOutput(
        _ output: XCResultTestOutput,
        rootDirectory: AbsolutePath?,
        xcresultPath: AbsolutePath
    ) async -> TestSummary {
        // Flatten all test nodes into test cases and extract suite/module durations
        var allTestCases: [TestCase] = []
        var suiteDurations: [String: Int] = [:]
        var moduleDurations: [String: Int] = [:]

        for testNode in output.testNodes {
            extractTestCases(from: testNode, module: nil, into: &allTestCases, suiteDurations: &suiteDurations, moduleDurations: &moduleDurations, rootDirectory: rootDirectory)
        }

        // Check if we need to extract Swift Testing durations (when duration is missing or 0)
        let needsSwiftTestingDurations = allTestCases.contains { testCase in
            testCase.duration == nil || testCase.duration == 0
        }

        let actionLogDurations: ([String: Int], [String: Int])
        var overallDuration: Int?
        if needsSwiftTestingDurations {
            let swiftTestingSuiteDurations: [String: Int]
            (allTestCases, swiftTestingSuiteDurations, actionLogDurations, overallDuration) = await updateWithSwiftTestingDurations(testCases: allTestCases, xcresultPath: xcresultPath)
            // Merge Swift Testing suite durations (they take precedence over XCTest durations)
            suiteDurations.merge(swiftTestingSuiteDurations) { _, new in new }
        } else {
            // Even if we don't need Swift Testing durations, we should extract module durations from action logs
            (actionLogDurations, overallDuration) = await extractActionLogDurations(xcresultPath: xcresultPath)
        }

        // Merge module durations from action logs (they take precedence over test node durations)
        moduleDurations.merge(actionLogDurations.0) { _, new in new }

        let overallStatus: TestStatus
        if allTestCases.contains(where: { $0.status == .failed }) {
            overallStatus = .failed
        } else if allTestCases.allSatisfy({ $0.status == .skipped }) {
            overallStatus = .skipped
        } else {
            overallStatus = .passed
        }

        let testModules = testModules(from: allTestCases, suiteDurations: suiteDurations, moduleDurations: moduleDurations)

        return TestSummary(
            testPlanName: output.testNodes.first?.name,
            status: overallStatus,
            duration: overallDuration,
            testModules: testModules
        )
    }

    private func extractTestCases(
        from node: TestNode,
        module: String?,
        into testCases: inout [TestCase],
        suiteDurations: inout [String: Int],
        moduleDurations: inout [String: Int],
        rootDirectory: AbsolutePath?
    ) {
        let currentModule = (node.nodeType == "Unit test bundle") ? node.name : module

        // Capture suite duration if this is a Test Suite node
        if node.nodeType == "Test Suite", let suiteName = node.name, let durationInSeconds = node.durationInSeconds {
            suiteDurations[suiteName] = secondsToMilliseconds(durationInSeconds)
        }

        if node.nodeType == "Test Case" {
            // This is an actual test case
            guard let name = node.name else { return }

            let suiteName = extractSuiteName(from: node.nodeIdentifier)
            let duration = node.durationInSeconds.map { secondsToMilliseconds($0) }
            let status = testStatus(from: node.result)
            let failures = extractFailures(from: node, rootDirectory: rootDirectory)

            let testCase = TestCase(
                name: name,
                testSuite: suiteName,
                module: currentModule,
                duration: duration,
                status: status,
                failures: failures
            )
            testCases.append(testCase)
        }

        // Recursively process children
        if let children = node.children {
            for child in children {
                extractTestCases(from: child, module: currentModule, into: &testCases, suiteDurations: &suiteDurations, moduleDurations: &moduleDurations, rootDirectory: rootDirectory)
            }
        }
    }

    private func extractSuiteName(from identifier: String?) -> String? {
        guard let identifier else { return nil }
        let components = identifier.split(separator: "/")
        return components.count >= 2 ? String(components[components.count - 2]) : nil
    }

    private func testStatus(from result: String?) -> TestStatus {
        switch result {
        case "Passed", "Expected Failure":
            return .passed
        case "Skipped":
            return .skipped
        default:
            return .failed
        }
    }

    private func extractFailures(from node: TestNode, rootDirectory: AbsolutePath?) -> [TestCaseFailure] {
        guard let children = node.children else { return [] }

        return children.compactMap { child in
            guard child.nodeType == "Failure Message",
                  let message = child.name
            else {
                return nil
            }

            // Parse file path and line number from message
            // Format: "File.swift:123: Error message"
            let components = message.components(separatedBy: ": ")
            if components.count >= 2 {
                let fileAndLine = components[0]
                let errorMessage = components.dropFirst().joined(separator: ": ")

                let fileComponents = fileAndLine.components(separatedBy: ":")
                if fileComponents.count >= 2 {
                    let filePath = fileComponents[0]
                    let lineNumber = Int(fileComponents[1]) ?? 0

                    // Convert file path to RelativePath
                    let relativePath: RelativePath?
                    if let absolutePath = try? AbsolutePath(validating: filePath) {
                        relativePath = absolutePath.relative(to: rootDirectory ?? AbsolutePath.root)
                    } else {
                        relativePath = nil
                    }

                    return TestCaseFailure(
                        message: errorMessage,
                        path: relativePath,
                        lineNumber: lineNumber,
                        issueType: nil
                    )
                }
            }

            return TestCaseFailure(
                message: message,
                path: nil,
                lineNumber: 0,
                issueType: nil
            )
        }
    }

    private func testModules(from testCases: [TestCase], suiteDurations: [String: Int], moduleDurations: [String: Int]) -> [TestModule] {
        let testCasesByModule = Dictionary(grouping: testCases) { testCase in
            testCase.module ?? "Unknown"
        }

        return testCasesByModule.map { moduleName, moduleTestCases in
            let moduleStatus: TestStatus = moduleTestCases.contains { $0.status == .failed } ? .failed : .passed
            // Use the module duration from the node if available, otherwise sum test case durations
            let moduleDuration = moduleDurations[moduleName] ?? moduleTestCases.compactMap(\.duration).reduce(0, +)

            let testCasesBySuite = Dictionary(grouping: moduleTestCases) { testCase in
                testCase.testSuite
            }

            let testSuites = testCasesBySuite.compactMap { suiteName, suiteTestCases -> TestSuite? in
                guard let suiteName else { return nil }
                let suiteStatus: TestStatus = suiteTestCases.contains { $0.status == .failed } ? .failed : .passed
                // Use the suite duration from the node if available, otherwise sum test case durations
                let suiteDuration = suiteDurations[suiteName] ?? suiteTestCases.compactMap(\.duration).reduce(0, +)
                return TestSuite(name: suiteName, status: suiteStatus, duration: suiteDuration)
            }

            return TestModule(
                name: moduleName,
                status: moduleStatus,
                duration: moduleDuration,
                testSuites: testSuites,
                testCases: moduleTestCases
            )
        }
    }

    // MARK: - Swift Testing Duration Extraction

    /// Swift Testing durations are not properly reported in xcresult, so we extract them from action logs
    private func updateWithSwiftTestingDurations(
        testCases: [TestCase],
        xcresultPath: AbsolutePath
    ) async -> ([TestCase], [String: Int], ([String: Int], [String: Int]), Int?) {
        do {
            // Get action logs using xcresulttool with --compact for standardized JSON output
            let logJsonString = try await commandRunner.run(
                arguments: [
                    "/usr/bin/xcrun", "xcresulttool",
                    "get", "log", "--type", "action",
                    "--compact",
                    "--path", xcresultPath.pathString,
                ]
            ).concatenatedString()

            guard let logData = logJsonString.data(using: .utf8) else {
                print("Warning: Failed to convert log output to data")
                return (testCases, [:], ([:], [:]), nil)
            }

            // Parse the action log JSON
            let actionLog: ActionLogSection
            do {
                actionLog = try JSONDecoder().decode(ActionLogSection.self, from: logData)
            } catch {
                print("Warning: Failed to parse action log JSON: \(error)")
                return (testCases, [:], ([:], [:]), nil)
            }

            // Extract top-level duration
            let overallDuration = actionLog.duration.map { secondsToMilliseconds($0) }

            // Collect all emittedOutput fields
            let emittedOutputs = actionLog.collectEmittedOutputs()

            // Extract module durations from the JSON structure
            let moduleDurationsMap = actionLog.extractModuleDurations(secondsToMilliseconds: secondsToMilliseconds)

            // Parse Swift Testing duration patterns from the emitted outputs
            let (testDurationsMap, suiteDurationsMap) = parseSwiftTestingDurations(from: emittedOutputs)

            // Update test cases with extracted durations
            let updatedTestCases = testCases.map { testCase in
                guard testCase.duration == nil || testCase.duration == 0 else {
                    return testCase
                }

                let testNameWithoutParens = testCase.name.replacingOccurrences(of: "()", with: "")
                if let duration = testDurationsMap[testNameWithoutParens] ?? testDurationsMap[testCase.name] {
                    var updatedTestCase = testCase
                    updatedTestCase.duration = duration
                    return updatedTestCase
                }

                return testCase
            }

            return (updatedTestCases, suiteDurationsMap, (moduleDurationsMap, [:]), overallDuration)
        } catch {
            // If we fail to get logs, just return the test cases as-is
            print("Warning: Failed to extract Swift Testing durations: \(error)")
            return (testCases, [:], ([:], [:]), nil)
        }
    }

    /// Extract module and suite durations from action logs
    private func extractActionLogDurations(xcresultPath: AbsolutePath) async -> (([String: Int], [String: Int]), Int?) {
        do {
            // Get action logs using xcresulttool with --compact for standardized JSON output
            let logJsonString = try await commandRunner.run(
                arguments: [
                    "/usr/bin/xcrun", "xcresulttool",
                    "get", "log", "--type", "action",
                    "--compact",
                    "--path", xcresultPath.pathString,
                ]
            ).concatenatedString()

            guard let logData = logJsonString.data(using: .utf8) else {
                print("Warning: Failed to convert log output to data")
                return (([:], [:]), nil)
            }

            // Parse the action log JSON
            let actionLog: ActionLogSection
            do {
                actionLog = try JSONDecoder().decode(ActionLogSection.self, from: logData)
            } catch {
                print("Warning: Failed to parse action log JSON: \(error)")
                return (([:], [:]), nil)
            }

            // Extract top-level duration
            let overallDuration = actionLog.duration.map { secondsToMilliseconds($0) }

            // Extract module durations from the JSON structure
            let moduleDurationsMap = actionLog.extractModuleDurations(secondsToMilliseconds: secondsToMilliseconds)

            return ((moduleDurationsMap, [:]), overallDuration)
        } catch {
            // If we fail to get logs, just return empty maps
            print("Warning: Failed to extract action log durations: \(error)")
            return (([:], [:]), nil)
        }
    }

    /// Parse Swift Testing test and suite durations from emitted outputs
    private func parseSwiftTestingDurations(from emittedOutputs: [String]) -> ([String: Int], [String: Int]) {
        var testDurationsMap: [String: Int] = [:]
        var suiteDurationsMap: [String: Int] = [:]

        // Pre-compiled regex patterns for Swift Testing test duration formats
        let testPatterns = [
            #"[✔✘] Test (\w+)\(\) (?:passed|failed) after ([\d.]+) seconds"#,
            #"✔ Test (\w+)\(\) passed after ([\d.]+) seconds"#,
            #"✘ Test (\w+)\(\) failed after ([\d.]+) seconds"#,
        ].compactMap { try? NSRegularExpression(pattern: $0, options: []) }

        // Pre-compiled regex patterns for Swift Testing suite duration formats
        let suitePatterns = [
            #"[✔✘] Suite (\w+) (?:passed|failed) after ([\d.]+) seconds"#,
            #"✔ Suite (\w+) passed after ([\d.]+) seconds"#,
            #"✘ Suite (\w+) failed after ([\d.]+) seconds"#,
        ].compactMap { try? NSRegularExpression(pattern: $0, options: []) }

        for output in emittedOutputs {
            let lines = output.components(separatedBy: .newlines)

            for line in lines {
                // Quick filter to skip irrelevant lines
                guard line.contains("seconds") else { continue }

                let range = NSRange(line.startIndex ..< line.endIndex, in: line)

                // Try matching test patterns
                if line.contains("Test") {
                    for regex in testPatterns {
                        if let match = regex.firstMatch(in: line, options: [], range: range),
                           let testNameRange = Range(match.range(at: 1), in: line),
                           let durationRange = Range(match.range(at: 2), in: line)
                        {
                            let testName = String(line[testNameRange])
                            let durationString = String(line[durationRange])

                            if let durationSeconds = Double(durationString) {
                                let durationMs = secondsToMilliseconds(durationSeconds)
                                // Only use the first occurrence (avoid duplicates)
                                if testDurationsMap[testName] == nil {
                                    testDurationsMap[testName] = durationMs
                                }
                                break
                            }
                        }
                    }
                }

                // Try matching suite patterns
                if line.contains("Suite") {
                    for regex in suitePatterns {
                        if let match = regex.firstMatch(in: line, options: [], range: range),
                           let suiteNameRange = Range(match.range(at: 1), in: line),
                           let durationRange = Range(match.range(at: 2), in: line)
                        {
                            let suiteName = String(line[suiteNameRange])
                            let durationString = String(line[durationRange])

                            if let durationSeconds = Double(durationString) {
                                let durationMs = secondsToMilliseconds(durationSeconds)
                                // Only use the first occurrence (avoid duplicates)
                                if suiteDurationsMap[suiteName] == nil {
                                    suiteDurationsMap[suiteName] = durationMs
                                }
                                break
                            }
                        }
                    }
                }
            }
        }

        return (testDurationsMap, suiteDurationsMap)
    }
}
