import Command
import FileSystem
import Foundation
import Mockable
import Path
import TuistSupport

enum XCResultServiceError: LocalizedError, Equatable {
    case failedToParseOutput(AbsolutePath)

    var errorDescription: String? {
        switch self {
        case let .failedToParseOutput(path):
            return "Failed to parse xcresult output at \(path.pathString)"
        }
    }
}

@Mockable
public protocol XCResultServicing {
    func parse(path: AbsolutePath, rootDirectory: AbsolutePath?) async throws -> TestSummary?
    func mostRecentXCResultFile(projectDerivedDataDirectory: AbsolutePath) async throws -> AbsolutePath?
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
        return (ms == 0 && seconds > 0) ? 1 : ms
    }

    private static let errorPatterns = [
        "failed: caught error: ",
        "caught error: ",
        "thrown error: ",
        "failed - caught error: ",
    ]

    private func parseFailureMessage(_ message: String) -> (issueType: TestCaseFailure.IssueType, cleanedMessage: String) {
        if let cleaned = cleanedMessage(from: message, matching: Self.errorPatterns) {
            return (.errorThrown, cleaned.trimmingQuotes())
        }

        if let cleaned = cleanedMessage(from: message, matching: ["issue recorded: "]) {
            return (.issueRecorded, cleaned)
        }

        if let cleaned = cleanedMessage(from: message, matching: ["expectation failed: "]) {
            return (.assertionFailure, cleaned)
        }

        return (.assertionFailure, message)
    }

    private func cleanedMessage(from message: String, matching patterns: [String]) -> String? {
        for pattern in patterns {
            guard message.localizedCaseInsensitiveContains(pattern) else { continue }
            return message.replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    public func mostRecentXCResultFile(projectDerivedDataDirectory: AbsolutePath)
        async throws -> AbsolutePath?
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

        return logsBuildDirectoryPath.appending(component: latestLog.fileName)
    }

    public func parse(path: AbsolutePath, rootDirectory: AbsolutePath?) async throws -> TestSummary? {
        let testOutput: XCResultTestOutput = try await fileSystem
            .runInTemporaryDirectory(prefix: "xcresult-test-results") { temporaryDirectory in
                let tempFile = temporaryDirectory.appending(component: "test-results.json")

                _ = try await commandRunner.run(
                    arguments: [
                        "/bin/sh", "-c",
                        "/usr/bin/xcrun xcresulttool get test-results tests --path '\(path.pathString)' > '\(tempFile.pathString)'",
                    ]
                ).concatenatedString()

                let outputString = try await fileSystem.readTextFile(at: tempFile)
                let jsonString = extractJSON(from: outputString)
                guard let jsonData = jsonString.data(using: .utf8) else {
                    throw XCResultServiceError.failedToParseOutput(path)
                }
                return try JSONDecoder().decode(XCResultTestOutput.self, from: jsonData)
            }

        return try await parseTestOutput(testOutput, rootDirectory: rootDirectory, xcresultPath: path)
    }

    private func extractJSON(from output: String) -> String {
        guard let jsonStartIndex = output.firstIndex(of: "{"),
              let jsonEndIndex = output.lastIndex(of: "}")
        else {
            return output
        }
        return String(output[jsonStartIndex ... jsonEndIndex])
    }

    private func parseTestOutput(
        _ output: XCResultTestOutput,
        rootDirectory: AbsolutePath?,
        xcresultPath: AbsolutePath
    ) async throws -> TestSummary {
        let actionLog = try await actionLog(from: xcresultPath)
        let failuresFromActionLog = actionLog.extractTestFailures(rootDirectory: rootDirectory)

        var allTestCases: [TestCase] = []
        var suiteDurations: [String: Int] = [:]
        var moduleDurations: [String: Int] = [:]

        for testNode in output.testNodes {
            extractTestCases(
                from: testNode,
                module: nil,
                into: &allTestCases,
                suiteDurations: &suiteDurations,
                moduleDurations: &moduleDurations,
                rootDirectory: rootDirectory,
                actionLogFailures: failuresFromActionLog
            )
        }

        let (updatedTestCases, swiftTestingSuiteDurations, swiftTestingModuleDurations, overallDuration) =
            updateWithSwiftTestingDurations(testCases: allTestCases, actionLog: actionLog)

        allTestCases = updatedTestCases
        suiteDurations.merge(swiftTestingSuiteDurations) { _, new in new }
        moduleDurations.merge(swiftTestingModuleDurations) { _, new in new }

        let overallStatus = overallStatus(from: allTestCases)
        let testModules = testModules(from: allTestCases, suiteDurations: suiteDurations, moduleDurations: moduleDurations)

        return TestSummary(
            testPlanName: output.testNodes.first?.name ?? actionLog.title?.components(separatedBy: .whitespacesAndNewlines).last,
            status: overallStatus,
            duration: overallDuration,
            testModules: testModules
        )
    }

    private func overallStatus(from testCases: [TestCase]) -> TestStatus {
        if testCases.contains(where: { $0.status == .failed }) {
            return .failed
        } else if testCases.allSatisfy({ $0.status == .skipped }) {
            return .skipped
        } else {
            return .passed
        }
    }

    private func extractTestCases(
        from node: TestNode,
        module: String?,
        into testCases: inout [TestCase],
        suiteDurations: inout [String: Int],
        moduleDurations: inout [String: Int],
        rootDirectory: AbsolutePath?,
        actionLogFailures: [String: [TestFailure]]
    ) {
        let currentModule = node.nodeType == "Unit test bundle" ? node.name : module

        captureSuiteDuration(from: node, into: &suiteDurations)

        if let testCase = testCase(
            from: node,
            module: currentModule,
            rootDirectory: rootDirectory,
            actionLogFailures: actionLogFailures
        ) {
            testCases.append(testCase)
        }

        for child in node.children ?? [] {
            extractTestCases(
                from: child,
                module: currentModule,
                into: &testCases,
                suiteDurations: &suiteDurations,
                moduleDurations: &moduleDurations,
                rootDirectory: rootDirectory,
                actionLogFailures: actionLogFailures
            )
        }
    }

    private func captureSuiteDuration(from node: TestNode, into suiteDurations: inout [String: Int]) {
        guard node.nodeType == "Test Suite",
              let suiteName = node.name,
              let durationInSeconds = node.durationInSeconds
        else { return }

        suiteDurations[suiteName] = secondsToMilliseconds(durationInSeconds)
    }

    private func testCase(
        from node: TestNode,
        module: String?,
        rootDirectory: AbsolutePath?,
        actionLogFailures: [String: [TestFailure]]
    ) -> TestCase? {
        guard node.nodeType == "Test Case", let name = node.name else { return nil }

        let suiteName = extractSuiteName(from: node.nodeIdentifier)
        let failures = testCaseFailures(
            testName: name,
            suiteName: suiteName,
            node: node,
            rootDirectory: rootDirectory,
            actionLogFailures: actionLogFailures
        )

        return TestCase(
            name: name,
            testSuite: suiteName,
            module: module,
            duration: node.durationInSeconds.map { secondsToMilliseconds($0) },
            status: testStatus(from: node.result),
            failures: failures
        )
    }

    private func testCaseFailures(
        testName: String,
        suiteName: String?,
        node: TestNode,
        rootDirectory: AbsolutePath?,
        actionLogFailures: [String: [TestFailure]]
    ) -> [TestCaseFailure] {
        let testIdentifier = suiteName.map { "\($0)/\(testName)" } ?? testName

        guard let actionLogFailureList = actionLogFailures[testIdentifier] else {
            return extractFailures(from: node, rootDirectory: rootDirectory)
        }

        return actionLogFailureList.map { failure in
            let (issueType, cleanedMessage) = parseFailureMessage(failure.message)
            return TestCaseFailure(
                message: cleanedMessage,
                path: failure.filePath,
                lineNumber: failure.lineNumber,
                issueType: issueType
            )
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
        (node.children ?? [])
            .filter { $0.nodeType == "Failure Message" }
            .compactMap(\.name)
            .map { failure(from: $0, rootDirectory: rootDirectory) }
    }

    private func failure(from message: String, rootDirectory: AbsolutePath?) -> TestCaseFailure {
        guard let location = parseFileLocation(from: message) else {
            let (issueType, cleanedMessage) = parseFailureMessage(message)
            return TestCaseFailure(message: cleanedMessage, path: nil, lineNumber: 0, issueType: issueType)
        }

        let relativePath = (try? AbsolutePath(validating: location.filePath))
            .map { $0.relative(to: rootDirectory ?? .root) }
        let (issueType, cleanedMessage) = parseFailureMessage(location.errorMessage)

        return TestCaseFailure(message: cleanedMessage, path: relativePath, lineNumber: location.lineNumber, issueType: issueType)
    }

    private func parseFileLocation(from message: String) -> FileLocation? {
        let components = message.components(separatedBy: ": ")
        guard components.count >= 2 else { return nil }

        let fileAndLine = components[0]
        let fileComponents = fileAndLine.components(separatedBy: ":")
        guard fileComponents.count >= 2 else { return nil }

        let filePath = fileComponents[0]
        let lineNumber = Int(fileComponents[1]) ?? 0
        let errorMessage = components.dropFirst().joined(separator: ": ")

        return FileLocation(filePath: filePath, lineNumber: lineNumber, errorMessage: errorMessage)
    }

    private func testModules(
        from testCases: [TestCase],
        suiteDurations: [String: Int],
        moduleDurations: [String: Int]
    ) -> [TestModule] {
        Dictionary(grouping: testCases) { $0.module ?? "Unknown" }
            .map { moduleName, moduleTestCases in
                testModule(
                    name: moduleName,
                    testCases: moduleTestCases,
                    suiteDurations: suiteDurations,
                    moduleDurations: moduleDurations
                )
            }
    }

    private func testModule(
        name: String,
        testCases: [TestCase],
        suiteDurations: [String: Int],
        moduleDurations: [String: Int]
    ) -> TestModule {
        let status: TestStatus = testCases.contains { $0.status == .failed } ? .failed : .passed
        let duration = moduleDurations[name] ?? testCases.compactMap(\.duration).reduce(0, +)
        let suites = testSuites(from: testCases, suiteDurations: suiteDurations)

        return TestModule(name: name, status: status, duration: duration, testSuites: suites, testCases: testCases)
    }

    private func testSuites(from testCases: [TestCase], suiteDurations: [String: Int]) -> [TestSuite] {
        Dictionary(grouping: testCases) { $0.testSuite }
            .compactMap { suiteName, suiteTestCases in
                guard let suiteName else { return nil }
                let status: TestStatus = suiteTestCases.contains { $0.status == .failed } ? .failed : .passed
                let duration = suiteDurations[suiteName] ?? suiteTestCases.compactMap(\.duration).reduce(0, +)
                return TestSuite(name: suiteName, status: status, duration: duration)
            }
    }

    private struct FileLocation {
        let filePath: String
        let lineNumber: Int
        let errorMessage: String
    }

    private func updateWithSwiftTestingDurations(
        testCases: [TestCase],
        actionLog: ActionLogSection
    ) -> ([TestCase], [String: Int], [String: Int], Int?) { // swiftlint:disable:this large_tuple
        let timestamps = actionLog.extractTestTimestamps()
        let emittedOutputs = actionLog.collectEmittedOutputs()
        let (testDurations, suiteDurations) = swiftTestingDurations(from: emittedOutputs)

        let overall = overallDuration(from: timestamps)
        let modules = moduleDurations(from: timestamps)
        let updatedTestCases = testCasesWithDurations(testCases, testDurations: testDurations)

        return (updatedTestCases, suiteDurations, modules, overall)
    }

    private func actionLog(from xcresultPath: AbsolutePath) async throws -> ActionLogSection {
        try await fileSystem.runInTemporaryDirectory(prefix: "xcresult-action-log") { temporaryDirectory in
            let tempFile = temporaryDirectory.appending(component: "action-log.json")

            let outputString = try await commandRunner.run(
                arguments: [
                    "/bin/sh", "-c",
                    "/usr/bin/xcrun xcresulttool get log --type action --compact --path '\(xcresultPath.pathString)' > '\(tempFile.pathString)'",
                ]
            ).concatenatedString()

            let logData = try await fileSystem.readFile(at: tempFile)
            return try JSONDecoder().decode(ActionLogSection.self, from: logData)
        }
    }

    private func overallDuration(from timestamps: ActionLogSection.TestTimestamps) -> Int? {
        guard let testStart = timestamps.earliestTestStart,
              let latestCompletion = timestamps.latestOverallCompletion
        else { return nil }

        return secondsToMilliseconds(latestCompletion - testStart)
    }

    private func moduleDurations(from timestamps: ActionLogSection.TestTimestamps) -> [String: Int] {
        var durations: [String: Int] = [:]
        for (moduleName, testStartTime) in timestamps.testTargetStartTimes {
            if let latestCompletion = timestamps.latestCompletionPerModule[moduleName] {
                durations[moduleName] = secondsToMilliseconds(latestCompletion - testStartTime)
            }
        }
        return durations
    }

    private func testCasesWithDurations(_ testCases: [TestCase], testDurations: [String: Int]) -> [TestCase] {
        testCases.map { testCase in
            guard testCase.duration == nil || testCase.duration == 0 else { return testCase }

            let testNameWithoutParens = testCase.name.replacingOccurrences(of: "()", with: "")
            guard let duration = testDurations[testNameWithoutParens] ?? testDurations[testCase.name] else {
                return testCase
            }

            var updated = testCase
            updated.duration = duration
            return updated
        }
    }

    // MARK: - Swift Testing Duration Parsing

    private static let testDurationPatterns = [
        #"[✔✘] Test (\w+)\(\) (?:passed|failed) after ([\d.]+) seconds"#,
        #"✔ Test (\w+)\(\) passed after ([\d.]+) seconds"#,
        #"✘ Test (\w+)\(\) failed after ([\d.]+) seconds"#,
        #"[✔✘] Test "([^"]+)" (?:passed|failed) after ([\d.]+) seconds"#,
        #"✔ Test "([^"]+)" passed after ([\d.]+) seconds"#,
        #"✘ Test "([^"]+)" failed after ([\d.]+) seconds"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: []) }

    private static let suiteDurationPatterns = [
        #"[✔✘] Suite (\w+) (?:passed|failed) after ([\d.]+) seconds"#,
        #"✔ Suite (\w+) passed after ([\d.]+) seconds"#,
        #"✘ Suite (\w+) failed after ([\d.]+) seconds"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: []) }

    private func swiftTestingDurations(from emittedOutputs: [String]) -> (tests: [String: Int], suites: [String: Int]) {
        var testDurations: [String: Int] = [:]
        var suiteDurations: [String: Int] = [:]

        let lines = emittedOutputs.flatMap { $0.components(separatedBy: .newlines) }
            .filter { $0.contains("seconds") }

        for line in lines {
            if line.contains("Test"), let (name, duration) = extractDuration(from: line, using: Self.testDurationPatterns) {
                testDurations[name] = testDurations[name] ?? duration
            }
            if line.contains("Suite"), let (name, duration) = extractDuration(from: line, using: Self.suiteDurationPatterns) {
                suiteDurations[name] = suiteDurations[name] ?? duration
            }
        }

        return (testDurations, suiteDurations)
    }

    private func extractDuration(from line: String, using patterns: [NSRegularExpression]) -> (name: String, duration: Int)? {
        let range = NSRange(line.startIndex ..< line.endIndex, in: line)

        for regex in patterns {
            guard let match = regex.firstMatch(in: line, options: [], range: range),
                  let nameRange = Range(match.range(at: 1), in: line),
                  let durationRange = Range(match.range(at: 2), in: line),
                  let durationSeconds = Double(String(line[durationRange]))
            else { continue }

            return (String(line[nameRange]), secondsToMilliseconds(durationSeconds))
        }

        return nil
    }
}

extension String {
    fileprivate func trimmingQuotes() -> String {
        guard hasPrefix("\""), hasSuffix("\"") else { return self }
        return String(dropFirst().dropLast())
    }
}
