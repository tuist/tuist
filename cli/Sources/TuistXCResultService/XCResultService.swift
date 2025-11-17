import Foundation
import Mockable
import Path
import XCResultKit
import FileSystem
import TuistXCActivityLog

@Mockable
public protocol XCResultServicing {
    func parse(path: AbsolutePath) -> InvocationRecord?
    func successfulTestTargets(invocationRecord: InvocationRecord) -> Set<String>
    func testSummary(invocationRecord: InvocationRecord) -> TestSummary
    func mostRecentXCResultFile(projectDerivedDataDirectory: AbsolutePath) async throws -> XCResultFile?
}

public struct TestSummary {
    public let scheme: String?
    public let status: TestStatus
    public let duration: Int?
    public let testCases: [TestCase]
    
    public init(scheme: String?, status: TestStatus, duration: Int?, testCases: [TestCase]) {
        self.scheme = scheme
        self.status = status
        self.duration = duration
        self.testCases = testCases
    }
}

struct SwiftTestingDurationInfo {
    let testName: String
    let duration: Double
    let timestamp: Double
    let logContent: String
}

public struct TestCase {
    public let name: String
    public let testSuite: String?
    public let module: String?
    public let duration: Int?
    public let status: TestStatus
    
    public init(name: String, testSuite: String?, module: String?, duration: Int?, status: TestStatus) {
        self.name = name
        self.testSuite = testSuite
        self.module = module
        self.duration = duration
        self.status = status
    }
}

public enum TestStatus {
    case passed
    case failed
    case skipped
}

public struct InvocationRecord {
    public struct ActionRecord {
        public let actionResult: Result
        public let startedTime: Date
        public let endedTime: Date

        public init(actionResult: Result, startedTime: Date, endedTime: Date) {
            self.actionResult = actionResult
            self.startedTime = startedTime
            self.endedTime = endedTime
        }

        init(result: XCResultKit.ActionRecord) {
            actionResult = .init(result: result.actionResult)
            startedTime = result.startedTime
            endedTime = result.endedTime
        }
    }

    public struct Result {
        public let testRefId: String?

        public init(testRefId: String?) {
            self.testRefId = testRefId
        }

        init(result: ActionResult) {
            testRefId = result.testsRef?.id
        }
    }

    public struct TestPlanRunSummaries {
        public let summaries: [TestPlanRunSummary]

        public init(summaries: [TestPlanRunSummary]) {
            self.summaries = summaries
        }

        init(testPlanRunSummaries: ActionTestPlanRunSummaries) {
            summaries = testPlanRunSummaries.summaries.map { .init(testPlanRunSummary: $0) }
        }
    }

    public struct TestPlanRunSummary {
        public let testableSummaries: [TestableSummary]

        public init(testableSummaries: [TestableSummary]) {
            self.testableSummaries = testableSummaries
        }

        init(testPlanRunSummary: ActionTestPlanRunSummary) {
            testableSummaries = testPlanRunSummary.testableSummaries.map { .init(testableSummary: $0) }
        }
    }

    public struct TestableSummary {
        public let targetName: String?
        public let tests: [TestSummaryGroup]

        public init(targetName: String, tests: [TestSummaryGroup]) {
            self.targetName = targetName
            self.tests = tests
        }

        init(testableSummary: ActionTestableSummary) {
            targetName = testableSummary.targetName
            tests = testableSummary.tests.map { .init(testSummaryGroup: $0) }
        }
    }

    public struct TestSummaryGroup {
        public let subtests: [TestMetadata]
        public let subtestGroups: [TestSummaryGroup]

        public init(subtests: [TestMetadata], subtestGroups: [TestSummaryGroup]) {
            self.subtests = subtests
            self.subtestGroups = subtestGroups
        }

        init(testSummaryGroup: ActionTestSummaryGroup) {
            subtests = testSummaryGroup.subtests.map { .init(testMetadata: $0) }
            subtestGroups = testSummaryGroup.subtestGroups.map { .init(testSummaryGroup: $0) }
        }
    }

    public struct TestMetadata {
        public let name: String?
        public let suiteName: String?
        public let testStatus: String
        public let duration: Int?

        public init(
            name: String?,
            suiteName: String?,
            testStatus: String,
            duration: Int?
        ) {
            self.name = name
            self.suiteName = suiteName
            self.testStatus = testStatus
            self.duration = duration
        }

        init(testMetadata: ActionTestMetadata) {
            name = testMetadata.name
            if let identifier = testMetadata.identifier {
                suiteName = Self.suiteName(from: identifier)
            } else {
                suiteName = nil
            }
            testStatus = testMetadata.testStatus
            duration = testMetadata.duration.map { Int($0 * 1000) }
        }
        
        private static func suiteName(from testIdentifier: String) -> String? {
            // Split the identifier by forward slashes
            let components = testIdentifier.split(separator: "/")
            
            // We need at least the following structure:
            // test://domain/target/[suite]/testMethod
            // If suite is optional, minimum is: test://domain/target/testMethod
            
            if components.count == 2 {
                return String(components[0])
            } else {
                return nil
            }
        }
    }

    public let actions: [ActionRecord]
    public let testSummaries: [TestPlanRunSummaries]
    public let path: URL

    public init(actions: [ActionRecord], testSummaries: [TestPlanRunSummaries], path: URL) {
        self.actions = actions
        self.testSummaries = testSummaries
        self.path = path
    }

    init(resultFile: XCResultFile, invocationRecord: ActionsInvocationRecord) {
        actions = invocationRecord.actions.map { .init(result: $0) }
        testSummaries = actions
            .compactMap(\.actionResult.testRefId)
            .compactMap { resultFile.getTestPlanRunSummaries(id: $0) }
            .map { TestPlanRunSummaries(testPlanRunSummaries: $0) }
        path = resultFile.url
    }
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
    
    public func parse(path: AbsolutePath) -> InvocationRecord? {
        let resultFile = XCResultFile(url: path.url)
        guard let invocationRecord = resultFile.getInvocationRecord() else { return nil }

        return .init(resultFile: resultFile, invocationRecord: invocationRecord)
    }

    public func successfulTestTargets(invocationRecord: InvocationRecord) -> Set<String> {
        var passingTargets = [String]()

        for testSummary in invocationRecord.testSummaries {
            for summary in testSummary.summaries {
                for testableSummary in summary.testableSummaries {
                    if testableSummary.tests.allSatisfy({ !$0.hasFailedTests }), let targetName = testableSummary.targetName {
                        passingTargets.append(targetName)
                    }
                }
            }
        }

        return Set(passingTargets)
    }
    
    public func testSummary(invocationRecord: InvocationRecord) -> TestSummary {
        var allTestCases: [TestCase] = []
        var hasFailedTests = false
        var hasSkippedTests = false
        
        // Extract test cases from all test summaries
        for testSummary in invocationRecord.testSummaries {
            for summary in testSummary.summaries {
                for testableSummary in summary.testableSummaries {
                    let module = testableSummary.targetName
                    let testCases = extractTestCases(from: testableSummary.tests, module: module)
                    allTestCases.append(contentsOf: testCases)
                }
            }
        }
        
        // Extract Swift Testing durations and update test cases if needed
        let resultFile = XCResultFile(url: invocationRecord.path)
        if let actionsInvocationRecord = resultFile.getInvocationRecord() {
            let swiftTestingDurations = extractSwiftTestingDurationsFromLogs(resultFile: resultFile, invocationRecord: actionsInvocationRecord)
            
            if !swiftTestingDurations.isEmpty {
                allTestCases = updateTestCasesWithSwiftTestingDurations(testCases: allTestCases, swiftTestingDurations: swiftTestingDurations)
            }
        }
        
        // Calculate overall status using test case results
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
        } else if hasSkippedTests && allTestCases.allSatisfy({ $0.status == .skipped }) {
            overallStatus = .skipped
        } else {
            overallStatus = .passed
        }
        
        // Calculate total duration from action records (top-level duration)
        let totalDuration = calculateOverallDuration(from: invocationRecord.actions)
        
        return TestSummary(
            scheme: nil,
            status: overallStatus,
            duration: totalDuration > 0 ? totalDuration : nil,
            testCases: allTestCases
        )
    }
    
    private func calculateOverallDuration(from actions: [InvocationRecord.ActionRecord]) -> Int {
        // Find the earliest start time and latest end time across all actions
        guard !actions.isEmpty else { return 0 }
        
        let startTime = actions.map(\.startedTime).min() ?? Date()
        let endTime = actions.map(\.endedTime).max() ?? Date()
        
        let duration = endTime.timeIntervalSince(startTime)
        return Int(duration * 1000) // Convert to milliseconds
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
                        status: testStatusFromString(testMetadata.testStatus)
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
    
    private func extractSwiftTestingDurationsFromLogs(resultFile: XCResultFile, invocationRecord: ActionsInvocationRecord) -> [SwiftTestingDurationInfo] {
        return extractDurationsFromAllReferences(resultFile: resultFile, invocationRecord: invocationRecord)
    }
    
    private func extractEmittedOutput(from line: String) -> String? {
        guard let emittedRange = line.range(of: "emittedOutput") else { return nil }
        
        let searchString = String(line[emittedRange.upperBound...])
        let pattern = #"K2:_vV(\d+):(.*?)(?:\]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        
        let range = NSRange(searchString.startIndex..<searchString.endIndex, in: searchString)
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
                #"✓ Suite (\w+) passed after ([\d.]+) seconds"#
            ]
            
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(line.startIndex..<line.endIndex, in: line)
                    if let match = regex.firstMatch(in: line, options: [], range: range) {
                        if let testNameRange = Range(match.range(at: 1), in: line),
                           let durationRange = Range(match.range(at: 2), in: line) {
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
    
    private func extractDurationsFromAllReferences(resultFile: XCResultFile, invocationRecord: ActionsInvocationRecord) -> [SwiftTestingDurationInfo] {
        var allDurations: [SwiftTestingDurationInfo] = []
        var allReferences: Set<String> = []
        
        for action in invocationRecord.actions {
            if let logRef = action.actionResult.logRef {
                allReferences.insert(logRef.id)
            }
            if let testsRef = action.actionResult.testsRef {
                allReferences.insert(testsRef.id)
            }
            if let timelineRef = action.actionResult.timelineRef {
                allReferences.insert(timelineRef.id)
            }
            if let diagnosticsRef = action.actionResult.diagnosticsRef {
                allReferences.insert(diagnosticsRef.id)
            }
            if let consoleLogRef = action.actionResult.consoleLogRef {
                allReferences.insert(consoleLogRef.id)
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
                        extractReferencesFromTestGroups(testableSummary.tests, newReferences: &referencesToExplore, exploredRefs: exploredRefs)
                    }
                }
            }
        }
        
        return allDurations
    }
    
    private func extractReferencesFromTestGroups(_ groups: [ActionTestSummaryGroup], newReferences: inout [String], exploredRefs: Set<String>) {
        for group in groups {
            for subtest in group.subtests {
                if let summaryRef = subtest.summaryRef, !exploredRefs.contains(summaryRef.id) {
                    newReferences.append(summaryRef.id)
                }
            }
            
            extractReferencesFromTestGroups(group.subtestGroups, newReferences: &newReferences, exploredRefs: exploredRefs)
        }
    }
    
    private func updateTestCasesWithSwiftTestingDurations(testCases: [TestCase], swiftTestingDurations: [SwiftTestingDurationInfo]) -> [TestCase] {
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
                    return TestCase(
                        name: testCase.name,
                        testSuite: testCase.testSuite,
                        module: testCase.module,
                        duration: swiftTestingDuration,
                        status: testCase.status
                    )
                }
            }
            
            return testCase
        }
    }
}

extension InvocationRecord.TestSummaryGroup {
    fileprivate var hasFailedTests: Bool {
        if subtests.first(where: \.isFailed) != nil {
            return true
        }
        if subtestGroups.first(where: \.hasFailedTests) != nil {
            return true
        }
        return false
    }
}

extension InvocationRecord.TestMetadata {
    fileprivate var isFailed: Bool {
        return isSuccessful == false && isSkipped == false
    }

    var isSuccessful: Bool {
        return testStatus == "Success" || testStatus == "Expected Failure"
    }

    private var isSkipped: Bool {
        return testStatus == "Skipped"
    }
}
