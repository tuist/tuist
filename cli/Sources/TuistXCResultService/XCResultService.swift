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

// swiftlint:disable:next type_body_length
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

        return testSummary(
            resultFile: resultFile,
            invocationRecord: invocationRecord,
            rootDirectory: rootDirectory
        )
    }

    private func testSummary(
        resultFile: XCResultFile,
        invocationRecord: ActionsInvocationRecord,
        rootDirectory: AbsolutePath?
    ) -> TestSummary {
        var allTestCases: [TestCase] = []

        let testPlanName = invocationRecord.actions.first?.testPlanName

        let testSummaries = invocationRecord.actions
            .compactMap(\.actionResult.testsRef?.id)
            .compactMap { resultFile.getTestPlanRunSummaries(id: $0) }

        for testPlanSummaries in testSummaries {
            for summary in testPlanSummaries.summaries {
                for testableSummary in summary.testableSummaries {
                    let module = testableSummary.targetName
                    let testCases = extractTestCases(
                        resultFile: resultFile,
                        from: testableSummary.tests,
                        module: module,
                        rootDirectory: rootDirectory
                    )
                    allTestCases.append(contentsOf: testCases)

                    let globalTestCases = extractTestCasesFromMetadata(
                        resultFile: resultFile,
                        from: testableSummary.globalTests,
                        module: module,
                        rootDirectory: rootDirectory
                    )
                    allTestCases.append(contentsOf: globalTestCases)
                }
            }
        }

        let swiftTestingDurations = extractSwiftTestingDurationsFromLogs(
            resultFile: resultFile,
            invocationRecord: invocationRecord
        )

        if !swiftTestingDurations.isEmpty {
            allTestCases = updateTestCasesWithSwiftTestingDurations(
                testCases: allTestCases,
                swiftTestingDurations: swiftTestingDurations
            )
        }

        let overallStatus: TestStatus
        if allTestCases.contains(where: { $0.status == .failed }) {
            overallStatus = .failed
        } else if allTestCases.allSatisfy({ $0.status == .skipped }) {
            overallStatus = .skipped
        } else {
            overallStatus = .passed
        }

        let totalDuration = calculateOverallDuration(from: invocationRecord.actions)
        let testModules = testModules(from: allTestCases)

        return TestSummary(
            testPlanName: testPlanName,
            status: overallStatus,
            duration: totalDuration > 0 ? totalDuration : nil,
            testModules: testModules
        )
    }

    private func testModules(from testCases: [TestCase]) -> [TestModule] {
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

    private func calculateOverallDuration(from actions: [ActionRecord]) -> Int {
        guard !actions.isEmpty else { return 0 }

        let startTime = actions.map(\.startedTime).min() ?? Date()
        let endTime = actions.map(\.endedTime).max() ?? Date()

        let duration = endTime.timeIntervalSince(startTime)
        return Int(duration * 1000)
    }

    private func extractTestCases(
        resultFile: XCResultFile,
        from testGroups: [ActionTestSummaryGroup],
        module: String?,
        rootDirectory: AbsolutePath?
    ) -> [TestCase] {
        var testCases: [TestCase] = []

        for group in testGroups {
            testCases.append(contentsOf: extractTestCasesFromMetadata(
                resultFile: resultFile,
                from: group.subtests,
                module: module,
                rootDirectory: rootDirectory
            ))

            testCases.append(contentsOf: extractTestCases(
                resultFile: resultFile,
                from: group.subtestGroups,
                module: module,
                rootDirectory: rootDirectory
            ))
        }

        return testCases
    }

    private func extractTestCasesFromMetadata(
        resultFile: XCResultFile,
        from testMetadataList: [ActionTestMetadata],
        module: String?,
        rootDirectory: AbsolutePath?
    ) -> [TestCase] {
        var testCases: [TestCase] = []

        for testMetadata in testMetadataList {
            if let testName = testMetadata.name {
                let suiteName = suiteName(from: testMetadata.identifier)
                let duration = testMetadata.duration.map { Int($0 * 1000) }
                let failures = extractFailures(
                    resultFile: resultFile,
                    testMetadata: testMetadata,
                    rootDirectory: rootDirectory
                )

                let testCase = TestCase(
                    name: testName,
                    testSuite: suiteName,
                    module: module,
                    duration: duration,
                    status: testStatusFromString(testMetadata.testStatus),
                    failures: failures
                )
                testCases.append(testCase)
            }
        }

        return testCases
    }

    private func suiteName(from testIdentifier: String?) -> String? {
        guard let testIdentifier else { return nil }
        let components = testIdentifier.split(separator: "/")

        if components.count == 2 {
            return String(components[0])
        } else {
            return nil
        }
    }

    private func extractFailures(
        resultFile: XCResultFile,
        testMetadata: ActionTestMetadata,
        rootDirectory: AbsolutePath?
    ) -> [TestCaseFailure] {
        guard let summaryRef = testMetadata.summaryRef,
              let summary = resultFile.getActionTestSummary(id: summaryRef.id)
        else {
            return []
        }

        return summary.failureSummaries.map {
            TestCaseFailure($0, rootDirectory: rootDirectory)
        }
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
