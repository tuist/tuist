import FileSystem
import Foundation
import Mockable
import Path
import TuistXCActivityLog
import XCResultKit

@Mockable
public protocol XCResultServicing {
    func parse(path: AbsolutePath, rootDirectory: AbsolutePath?) -> TestSummary?
    func mostRecentXCResultFile(projectDerivedDataDirectory: AbsolutePath) async throws -> XCResultFile?
}

struct SwiftTestingDurationInfo {
    let testName: String
    let duration: Double
    let timestamp: Double
    let logContent: String
}

public struct XCResultService: XCResultServicing {
    private let fileSystem: FileSysteming

    public init(
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.fileSystem = fileSystem
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

    public func parse(path: AbsolutePath, rootDirectory: AbsolutePath?) -> TestSummary? {
        let resultFile = XCResultFile(url: path.url)
        guard let invocationRecord = resultFile.getInvocationRecord() else { return nil }

        let parsedRecord = InvocationRecord(
            resultFile: resultFile,
            invocationRecord: invocationRecord,
            rootDirectory: rootDirectory
        )
        return testSummary(invocationRecord: parsedRecord)
    }

    private func testSummary(invocationRecord: InvocationRecord) -> TestSummary {
        var allTestCases: [TestCase] = []
        var hasFailedTests = false
        var hasSkippedTests = false

        let testPlanName = invocationRecord.actions.first?.testPlanName

        for testSummary in invocationRecord.testSummaries {
            for summary in testSummary.summaries {
                for testableSummary in summary.testableSummaries {
                    let module = testableSummary.targetName
                    let testCases = extractTestCases(from: testableSummary.tests, module: module)
                    allTestCases.append(contentsOf: testCases)
                }
            }
        }

        let resultFile = XCResultFile(url: invocationRecord.path)
        if let actionsInvocationRecord = resultFile.getInvocationRecord() {
            let swiftTestingDurations = extractSwiftTestingDurationsFromLogs(
                resultFile: resultFile,
                invocationRecord: actionsInvocationRecord
            )

            if !swiftTestingDurations.isEmpty {
                allTestCases = updateTestCasesWithSwiftTestingDurations(
                    testCases: allTestCases,
                    swiftTestingDurations: swiftTestingDurations
                )
            }
        }

        for testCase in allTestCases {
            switch testCase.status {
            case .failed:
                hasFailedTests = true
            case .skipped:
                hasSkippedTests = true
            case .passed:
                break
            }
        }

        let overallStatus: TestStatus
        if hasFailedTests {
            overallStatus = .failed
        } else if hasSkippedTests, allTestCases.allSatisfy({ $0.status == .skipped }) {
            overallStatus = .skipped
        } else {
            overallStatus = .passed
        }

        let totalDuration = calculateOverallDuration(from: invocationRecord.actions)
        let testModules = buildTestModules(from: allTestCases)

        return TestSummary(
            testPlanName: testPlanName,
            status: overallStatus,
            duration: totalDuration > 0 ? totalDuration : nil,
            testModules: testModules
        )
    }

    private func buildTestModules(from testCases: [TestCase]) -> [TestModule] {
        let testCasesByModule = Dictionary(grouping: testCases) { testCase in
            testCase.module ?? "Unknown"
        }

        return testCasesByModule.map { moduleName, moduleTestCases in
            let moduleStatus: TestStatus = moduleTestCases.contains { $0.status == .failed } ? .failed : .passed
            let moduleDuration = moduleTestCases.compactMap(\.duration).reduce(0, +)

            let testCasesBySuite = Dictionary(grouping: moduleTestCases) { testCase in
                testCase.testSuite
            }

            let testSuites = testCasesBySuite.compactMap { suiteName, suiteTestCases -> TestSuite? in
                guard let suiteName else { return nil }
                let suiteStatus: TestStatus = suiteTestCases.contains { $0.status == .failed } ? .failed : .passed
                let suiteDuration = suiteTestCases.compactMap(\.duration).reduce(0, +)
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

    private func calculateOverallDuration(from actions: [InvocationRecord.ActionRecord]) -> Int {
        guard !actions.isEmpty else { return 0 }

        let startTime = actions.map(\.startedTime).min() ?? Date()
        let endTime = actions.map(\.endedTime).max() ?? Date()

        let duration = endTime.timeIntervalSince(startTime)
        return Int(duration * 1000)
    }

    private func extractTestCases(from testGroups: [InvocationRecord.TestSummaryGroup], module: String?) -> [TestCase] {
        var testCases: [TestCase] = []

        for group in testGroups {
            for testMetadata in group.subtests {
                if let testName = testMetadata.name {
                    let testCase = TestCase(
                        name: testName,
                        testSuite: testMetadata.suiteName,
                        module: module,
                        duration: testMetadata.duration,
                        status: testStatusFromString(testMetadata.testStatus),
                        failures: testMetadata.failures
                    )
                    testCases.append(testCase)
                }
            }

            testCases.append(contentsOf: extractTestCases(from: group.subtestGroups, module: module))
        }

        return testCases
    }

    private func testStatusFromString(_ statusString: String) -> TestStatus {
        switch statusString {
        case "Success", "Expected Failure":
            return .passed
        case "Skipped":
            return .skipped
        default:
            return .failed
        }
    }

    /// The XCResult reporting of durations of Swift Testing tests is currently broken, so we need to extract the durations from
    /// the logs.
    /// We should keep an eye on new Xcode versions and hopefully, this will eventually get fixed and we will be able to remove
    /// all of the related code.
    private func extractSwiftTestingDurationsFromLogs(
        resultFile: XCResultFile,
        invocationRecord: ActionsInvocationRecord
    ) -> [SwiftTestingDurationInfo] {
        return extractDurationsFromAllReferences(resultFile: resultFile, invocationRecord: invocationRecord)
    }

    private func extractEmittedOutput(from line: String) -> String? {
        guard let emittedRange = line.range(of: "emittedOutput") else { return nil }

        let searchString = String(line[emittedRange.upperBound...])
        let pattern = #"K2:_vV(\d+):(.*?)(?:\]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }

        let range = NSRange(searchString.startIndex ..< searchString.endIndex, in: searchString)
        guard let match = regex.firstMatch(in: searchString, options: [], range: range) else { return nil }

        guard let lengthRange = Range(match.range(at: 1), in: searchString),
              let contentRange = Range(match.range(at: 2), in: searchString) else { return nil }

        let lengthString = String(searchString[lengthRange])
        let content = String(searchString[contentRange])

        guard let expectedLength = Int(lengthString) else { return nil }

        let extractedContent = String(content.prefix(expectedLength))
        return extractedContent
    }

    private func parseSwiftTestingFromConsoleOutput(_ consoleOutput: String) -> [SwiftTestingDurationInfo] {
        var durations: [SwiftTestingDurationInfo] = []
        let lines = consoleOutput.components(separatedBy: .newlines)

        for line in lines {
            let patterns = [
                #"[✓✘] Test (\w+)\(\) (?:passed|failed) after ([\d.]+) seconds"#,
                #"[✓✘] Suite (\w+) (?:passed|failed) after ([\d.]+) seconds"#,
                #"(\w+)\(\) (?:passed|failed) after ([\d.]+) seconds"#,
                #"Test (\w+) (?:passed|failed) after ([\d.]+) seconds"#,
                #"✘ Test (\w+)\(\) failed after ([\d.]+) seconds"#,
                #"✓ Test (\w+)\(\) passed after ([\d.]+) seconds"#,
                #"✘ Suite (\w+) failed after ([\d.]+) seconds"#,
                #"✓ Suite (\w+) passed after ([\d.]+) seconds"#,
            ]

            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(line.startIndex ..< line.endIndex, in: line)
                    if let match = regex.firstMatch(in: line, options: [], range: range) {
                        if let testNameRange = Range(match.range(at: 1), in: line),
                           let durationRange = Range(match.range(at: 2), in: line)
                        {
                            let testName = String(line[testNameRange])
                            let durationString = String(line[durationRange])

                            if let duration = Double(durationString) {
                                let durationInfo = SwiftTestingDurationInfo(
                                    testName: testName,
                                    duration: duration,
                                    timestamp: Date().timeIntervalSince1970,
                                    logContent: line
                                )
                                durations.append(durationInfo)
                                break
                            }
                        }
                    }
                }
            }
        }

        return durations
    }

    private func extractDurationsFromAllReferences(
        resultFile: XCResultFile,
        invocationRecord: ActionsInvocationRecord
    ) -> [SwiftTestingDurationInfo] {
        var allDurations: [SwiftTestingDurationInfo] = []
        var allReferences: Set<String> = []

        for action in invocationRecord.actions {
            if let logRef = action.actionResult.logRef {
                allReferences.insert(logRef.id)
            }
        }

        var exploredRefs: Set<String> = []
        var referencesToExplore = Array(allReferences)

        while !referencesToExplore.isEmpty {
            let currentRef = referencesToExplore.removeFirst()

            if exploredRefs.contains(currentRef) {
                continue
            }
            exploredRefs.insert(currentRef)

            if let payload = resultFile.getPayload(id: currentRef) {
                if let text = String(data: payload, encoding: .utf8) {
                    let lines = text.components(separatedBy: .newlines)

                    for line in lines {
                        if line.contains("emittedOutput") {
                            if let emittedContent = extractEmittedOutput(from: line) {
                                let consoleDurations = parseSwiftTestingFromConsoleOutput(emittedContent)
                                allDurations.append(contentsOf: consoleDurations)
                            }
                        }

                        if line.contains("✓") || line.contains("✘") || (line.contains("test") && line.contains("seconds")) {
                            let consoleDurations = parseSwiftTestingFromConsoleOutput(line)
                            allDurations.append(contentsOf: consoleDurations)
                        }
                    }
                }
            }

            if let testPlanSummaries = resultFile.getTestPlanRunSummaries(id: currentRef) {
                for summary in testPlanSummaries.summaries {
                    for testableSummary in summary.testableSummaries {
                        extractReferencesFromTestGroups(
                            testableSummary.tests,
                            newReferences: &referencesToExplore,
                            exploredRefs: exploredRefs
                        )
                    }
                }
            }
        }

        return allDurations
    }

    private func extractReferencesFromTestGroups(
        _ groups: [ActionTestSummaryGroup],
        newReferences: inout [String],
        exploredRefs: Set<String>
    ) {
        for group in groups {
            for subtest in group.subtests {
                if let summaryRef = subtest.summaryRef, !exploredRefs.contains(summaryRef.id) {
                    newReferences.append(summaryRef.id)
                }
            }

            extractReferencesFromTestGroups(group.subtestGroups, newReferences: &newReferences, exploredRefs: exploredRefs)
        }
    }

    private func updateTestCasesWithSwiftTestingDurations(
        testCases: [TestCase],
        swiftTestingDurations: [SwiftTestingDurationInfo]
    ) -> [TestCase] {
        var durationMap: [String: Int] = [:]
        for swiftTestingDuration in swiftTestingDurations {
            let testName = swiftTestingDuration.testName
            let durationMs = Int(swiftTestingDuration.duration * 1000)

            if !swiftTestingDuration.logContent.contains("Suite") {
                if durationMap[testName] == nil {
                    durationMap[testName] = durationMs
                }
            }
        }

        return testCases.map { testCase in
            let testNameWithoutParens = testCase.name.replacingOccurrences(of: "()", with: "")

            if testCase.duration == nil || testCase.duration == 0 {
                if let swiftTestingDuration = durationMap[testNameWithoutParens] ?? durationMap[testCase.name] {
                    var testCase = testCase
                    testCase.duration = swiftTestingDuration
                    return testCase
                }
            }

            return testCase
        }
    }
}
