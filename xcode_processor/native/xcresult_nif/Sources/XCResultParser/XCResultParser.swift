import Foundation

enum XCResultParserError: LocalizedError {
    case failedToParseOutput(String)
    case xcresulttoolFailed(String)

    var errorDescription: String? {
        switch self {
        case let .failedToParseOutput(path):
            return "Failed to parse xcresult output at \(path)"
        case let .xcresulttoolFailed(message):
            return "xcresulttool failed: \(message)"
        }
    }
}

public struct XCResultParser: Sendable {
    private let ipsCrashReportParser: IPSCrashReportParser

    public init() {
        self.ipsCrashReportParser = IPSCrashReportParser()
    }

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

    private func parseFailureMessage(_ message: String) -> (
        issueType: TestCaseFailure.IssueType, cleanedMessage: String
    ) {
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

    public func parse(xcresultPath: String, rootDirectory: String) async throws -> TestSummary {
        let testOutput = try await parseTestResults(xcresultPath: xcresultPath)
        return try await parseTestOutput(
            testOutput,
            rootDirectory: rootDirectory,
            xcresultPath: xcresultPath
        )
    }

    private func parseTestResults(xcresultPath: String) async throws -> XCResultTestOutput {
        let tempDir = NSTemporaryDirectory() + "xcresult-test-results-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let tempFile = tempDir + "/test-results.json"
        let command =
            "/usr/bin/xcrun xcresulttool get test-results tests --path '\(xcresultPath)' > '\(tempFile)'"

        try runShellCommand(command)

        let outputData = try Data(contentsOf: URL(fileURLWithPath: tempFile))
        let outputString = String(data: outputData, encoding: .utf8) ?? ""
        let jsonString = extractJSON(from: outputString)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw XCResultParserError.failedToParseOutput(xcresultPath)
        }
        return try JSONDecoder().decode(XCResultTestOutput.self, from: jsonData)
    }

    private func extractJSON(from output: String) -> String {
        guard let jsonStartIndex = output.firstIndex(of: "{"),
            let jsonEndIndex = output.lastIndex(of: "}")
        else {
            return output
        }
        return String(output[jsonStartIndex...jsonEndIndex])
    }

    private func parseTestOutput(
        _ output: XCResultTestOutput,
        rootDirectory: String,
        xcresultPath: String
    ) async throws -> TestSummary {
        let actionLog = try await fetchActionLog(from: xcresultPath)
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

        let (updatedTestCases, swiftTestingSuiteDurations, swiftTestingModuleDurations,
            overallDuration) =
            updateWithSwiftTestingDurations(testCases: allTestCases, actionLog: actionLog)

        allTestCases = updatedTestCases
        suiteDurations.merge(swiftTestingSuiteDurations) { _, new in new }
        moduleDurations.merge(swiftTestingModuleDurations) { _, new in new }

        let extractedAttachments = await attachmentsByTestIdentifiers(from: xcresultPath)

        allTestCases = allTestCases.map { testCase in
            let testIdentifier = normalizeTestIdentifier(
                testCase.testSuite.map { "\($0)/\(testCase.name)" } ?? testCase.name
            )
            var testCase = testCase
            testCase.crashReport = extractedAttachments.crashReports[testIdentifier]
            testCase.attachments = extractedAttachments.attachments[testIdentifier] ?? []
            return testCase
        }

        let overallStatus = overallStatus(from: allTestCases)
        let testModules = testModules(
            from: allTestCases,
            suiteDurations: suiteDurations,
            moduleDurations: moduleDurations
        )

        return TestSummary(
            testPlanName: output.testNodes.first?.name
                ?? actionLog.title?.components(separatedBy: .whitespacesAndNewlines).last,
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
        rootDirectory: String,
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

    private func captureSuiteDuration(
        from node: TestNode, into suiteDurations: inout [String: Int]
    ) {
        guard node.nodeType == "Test Suite",
            let suiteName = node.name,
            let durationInSeconds = node.durationInSeconds
        else { return }

        suiteDurations[suiteName] = secondsToMilliseconds(durationInSeconds)
    }

    private func testCase(
        from node: TestNode,
        module: String?,
        rootDirectory: String,
        actionLogFailures: [String: [TestFailure]]
    ) -> TestCase? {
        guard node.nodeType == "Test Case", let name = node.name else { return nil }

        let suiteName = extractSuiteName(from: node.nodeIdentifier)

        let repetitionNodes = (node.children ?? []).filter { $0.nodeType == "Repetition" }

        let repetitions: [TestCaseRepetition] = repetitionNodes.enumerated().compactMap {
            index, repNode in
            guard let repName = repNode.name, let repResult = repNode.result else { return nil }

            let repStatus = testStatus(from: repResult)
            let repDuration = repNode.durationInSeconds.map { secondsToMilliseconds($0) } ?? 0
            let repFailures = extractFailures(from: repNode, rootDirectory: rootDirectory)

            return TestCaseRepetition(
                repetitionNumber: index + 1,
                name: repName,
                status: repStatus,
                duration: repDuration,
                failures: repFailures
            )
        }

        let failures: [TestCaseFailure]
        let failedRepetitions = repetitions.filter { $0.status == .failed }
        if !failedRepetitions.isEmpty {
            failures = failedRepetitions.flatMap(\.failures)
        } else {
            failures = testCaseFailures(
                testName: name,
                suiteName: suiteName,
                node: node,
                rootDirectory: rootDirectory,
                actionLogFailures: actionLogFailures
            )
        }

        return TestCase(
            name: name,
            testSuite: suiteName,
            module: module,
            duration: node.durationInSeconds.map { secondsToMilliseconds($0) },
            status: testStatus(from: node.result),
            failures: failures,
            repetitions: repetitions
        )
    }

    private func testCaseFailures(
        testName: String,
        suiteName: String?,
        node: TestNode,
        rootDirectory: String,
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

    private func extractFailures(
        from node: TestNode, rootDirectory: String
    ) -> [TestCaseFailure] {
        (node.children ?? [])
            .filter { $0.nodeType == "Failure Message" }
            .compactMap(\.name)
            .map { failure(from: $0, rootDirectory: rootDirectory) }
    }

    private func failure(from message: String, rootDirectory: String) -> TestCaseFailure {
        guard let location = parseFileLocation(from: message) else {
            let (issueType, cleanedMessage) = parseFailureMessage(message)
            return TestCaseFailure(
                message: cleanedMessage, path: nil, lineNumber: 0, issueType: issueType
            )
        }

        let relativePath = makeRelativePath(location.filePath, relativeTo: rootDirectory)
        let (issueType, cleanedMessage) = parseFailureMessage(location.errorMessage)

        return TestCaseFailure(
            message: cleanedMessage,
            path: relativePath,
            lineNumber: location.lineNumber,
            issueType: issueType
        )
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

        return FileLocation(
            filePath: filePath, lineNumber: lineNumber, errorMessage: errorMessage
        )
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

        return TestModule(
            name: name, status: status, duration: duration, testSuites: suites,
            testCases: testCases
        )
    }

    private func testSuites(
        from testCases: [TestCase], suiteDurations: [String: Int]
    ) -> [TestSuite] {
        Dictionary(grouping: testCases) { $0.testSuite }
            .compactMap { suiteName, suiteTestCases in
                guard let suiteName else { return nil }
                let status: TestStatus =
                    suiteTestCases.contains { $0.status == .failed } ? .failed : .passed
                let duration =
                    suiteDurations[suiteName]
                    ?? suiteTestCases.compactMap(\.duration).reduce(0, +)
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
    ) -> ([TestCase], [String: Int], [String: Int], Int?) {
        let emittedOutputs = actionLog.collectEmittedOutputs()
        let (testDurations, suiteDurations) = swiftTestingDurations(from: emittedOutputs)

        let actionLogDurations = actionLog.extractTestDurations()
        let overall =
            actionLogDurations.overallDuration
            ?? actionLog.duration.map { secondsToMilliseconds($0) }
        let modules = actionLogDurations.moduleDurations
        let updatedTestCases = testCasesWithDurations(testCases, testDurations: testDurations)

        return (updatedTestCases, suiteDurations, modules, overall)
    }

    private func fetchActionLog(from xcresultPath: String) async throws -> ActionLogSection {
        let tempDir = NSTemporaryDirectory() + "xcresult-action-log-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let tempFile = tempDir + "/action-log.json"
        let command =
            "/usr/bin/xcrun xcresulttool get log --type action --compact --path '\(xcresultPath)' > '\(tempFile)'"

        try runShellCommand(command)

        let logData = try Data(contentsOf: URL(fileURLWithPath: tempFile))
        return try JSONDecoder().decode(ActionLogSection.self, from: logData)
    }

    private func testCasesWithDurations(
        _ testCases: [TestCase], testDurations: [String: Int]
    ) -> [TestCase] {
        testCases.map { testCase in
            guard testCase.duration == nil || testCase.duration == 0 else { return testCase }

            let testNameWithoutParens = testCase.name.replacingOccurrences(of: "()", with: "")
            guard
                let duration = testDurations[testNameWithoutParens]
                    ?? testDurations[testCase.name]
            else {
                return testCase
            }

            var updated = testCase
            updated.duration = duration
            return updated
        }
    }

    // MARK: - Crash Attachment Extraction

    private struct AttachmentManifest: Decodable, Sendable {
        let testIdentifier: String?
        let attachments: [Attachment]

        struct Attachment: Decodable, Sendable {
            let exportedFileName: String
            let suggestedHumanReadableName: String?
            let isAssociatedWithFailure: Bool?
            let repetitionNumber: Int?
        }
    }

    private func attachmentsByTestIdentifiers(
        from xcresultPath: String
    ) async -> (crashReports: [String: CrashReport], attachments: [String: [TestAttachment]]) {
        do {
            let tempDir = NSTemporaryDirectory() + "xcresult-attachments-\(UUID().uuidString)"
            try FileManager.default.createDirectory(
                atPath: tempDir,
                withIntermediateDirectories: true
            )

            let command =
                "/usr/bin/xcrun xcresulttool export attachments --path '\(xcresultPath)' --output-path '\(tempDir)' 2>/dev/null"
            try runShellCommand(command)

            let manifestPath = tempDir + "/manifest.json"
            guard FileManager.default.fileExists(atPath: manifestPath) else {
                return ([:], [:])
            }

            let manifestData = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
            let manifestEntries = try JSONDecoder().decode(
                [AttachmentManifest].self, from: manifestData
            )

            var crashReportsByTestIdentifier: [String: CrashReport] = [:]
            var attachmentsByTestIdentifier: [String: [TestAttachment]] = [:]

            convertCgBIPNGs(in: tempDir, manifestEntries: manifestEntries)

            for entry in manifestEntries {
                guard let testIdentifier = entry.testIdentifier else { continue }
                let normalizedIdentifier = normalizeTestIdentifier(testIdentifier)

                for attachment in entry.attachments {
                    let filePath = tempDir + "/" + attachment.exportedFileName
                    guard FileManager.default.fileExists(atPath: filePath) else { continue }

                    let testAttachment = TestAttachment(
                        filePath: filePath,
                        fileName: attachment.suggestedHumanReadableName
                            ?? attachment.exportedFileName,
                        repetitionNumber: attachment.repetitionNumber
                    )
                    attachmentsByTestIdentifier[normalizedIdentifier, default: []].append(
                        testAttachment
                    )

                    if attachment.exportedFileName.hasSuffix(".ips"),
                        attachment.isAssociatedWithFailure == true
                    {
                        let content = try String(contentsOfFile: filePath, encoding: .utf8)
                        let crashReportData = try ipsCrashReportParser.parse(content)
                        crashReportsByTestIdentifier[normalizedIdentifier] = CrashReport(
                            exceptionType: crashReportData.exceptionType,
                            signal: crashReportData.signal,
                            exceptionSubtype: crashReportData.exceptionSubtype,
                            filePath: filePath,
                            triggeredThreadFrames: crashReportData.triggeredThreadFrames
                        )
                    }
                }
            }

            return (crashReportsByTestIdentifier, attachmentsByTestIdentifier)
        } catch {
            return ([:], [:])
        }
    }

    private func convertCgBIPNGs(in directory: String, manifestEntries: [AttachmentManifest]) {
        let pngFileNames = manifestEntries
            .flatMap(\.attachments)
            .map(\.exportedFileName)
            .filter { $0.lowercased().hasSuffix(".png") }

        for fileName in pngFileNames {
            let filePath = directory + "/" + fileName
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            process.arguments = ["-s", "format", "png", filePath, "--out", filePath]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    private func normalizeTestIdentifier(_ identifier: String) -> String {
        var normalized = identifier
        if normalized.hasSuffix("()") {
            normalized = String(normalized.dropLast(2))
        }
        let components = normalized.split(separator: "/")
        if components.count >= 2 {
            return "\(components[components.count - 2])/\(components[components.count - 1])"
        }
        return normalized
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

    private func swiftTestingDurations(from emittedOutputs: [String]) -> (
        tests: [String: Int], suites: [String: Int]
    ) {
        var testDurations: [String: Int] = [:]
        var suiteDurations: [String: Int] = [:]

        let lines = emittedOutputs.flatMap { $0.components(separatedBy: .newlines) }
            .filter { $0.contains("seconds") }

        for line in lines {
            if line.contains("Test"),
                let (name, duration) = extractDuration(
                    from: line, using: Self.testDurationPatterns
                )
            {
                testDurations[name] = testDurations[name] ?? duration
            }
            if line.contains("Suite"),
                let (name, duration) = extractDuration(
                    from: line, using: Self.suiteDurationPatterns
                )
            {
                suiteDurations[name] = suiteDurations[name] ?? duration
            }
        }

        return (testDurations, suiteDurations)
    }

    private func extractDuration(
        from line: String, using patterns: [NSRegularExpression]
    ) -> (name: String, duration: Int)? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)

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

    // MARK: - Shell Command Execution

    private func runShellCommand(_ command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw XCResultParserError.xcresulttoolFailed(errorMessage)
        }
    }

    private func makeRelativePath(_ path: String, relativeTo root: String) -> String? {
        guard path.hasPrefix("/") else { return path }
        let rootWithSlash = root.hasSuffix("/") ? root : root + "/"
        if path.hasPrefix(rootWithSlash) {
            return String(path.dropFirst(rootWithSlash.count))
        }
        return path
    }
}

extension String {
    fileprivate func trimmingQuotes() -> String {
        guard hasPrefix("\""), hasSuffix("\"") else { return self }
        return String(dropFirst().dropLast())
    }
}
