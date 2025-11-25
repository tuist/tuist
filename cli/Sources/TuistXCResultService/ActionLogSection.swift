import Foundation
import Path

struct ActionLogSection: Codable {
    let subsections: [ActionLogSection]?
    let commandInvocationDetails: CommandInvocationDetails?
    let testDetails: TestDetails?
    let messages: [Message]?
    let duration: Double?
    let startTime: Double?
    let title: String?
    let location: Location?

    struct CommandInvocationDetails: Codable {
        let emittedOutput: String?
    }

    struct TestDetails: Codable {
        let emittedOutput: String?
        let runnablePath: String?
        let testName: String?
        let suiteName: String?
    }

    struct Message: Codable {
        let type: String?
        let title: String?
        let shortTitle: String?
        let location: Location?
    }

    struct Location: Codable {
        let url: String?
    }

    struct TestTimestamps {
        let testTargetStartTimes: [String: Double]
        let earliestTestStart: Double?
        let latestOverallCompletion: Double?
        let latestCompletionPerModule: [String: Double]
    }
}

/// Helper to recursively search for test-related emittedOutput
extension ActionLogSection {
    func collectEmittedOutputs() -> [String] {
        var outputs: [String] = []

        if let emittedOutput = testDetails?.emittedOutput, !emittedOutput.isEmpty {
            outputs.append(emittedOutput)
        }

        if let subsections {
            for subsection in subsections {
                outputs.append(contentsOf: subsection.collectEmittedOutputs())
            }
        }

        return outputs
    }

    /// Extract test target start times and suite completion timestamps
    /// Returns start times per module, earliest overall start, and latest completion timestamps
    func extractTestTimestamps() -> TestTimestamps {
        var testTargetStartTimes: [String: Double] = [:]
        var earliestTestStart: Double?
        var latestOverallCompletion: Double?
        var latestCompletionPerModule: [String: Double] = [:]

        extractTestTimestampsRecursive(
            testTargetStartTimes: &testTargetStartTimes,
            earliestTestStart: &earliestTestStart,
            latestOverallCompletion: &latestOverallCompletion,
            latestCompletionPerModule: &latestCompletionPerModule
        )

        return TestTimestamps(
            testTargetStartTimes: testTargetStartTimes,
            earliestTestStart: earliestTestStart,
            latestOverallCompletion: latestOverallCompletion,
            latestCompletionPerModule: latestCompletionPerModule
        )
    }

    private func extractTestTimestampsRecursive(
        testTargetStartTimes: inout [String: Double],
        earliestTestStart: inout Double?,
        latestOverallCompletion: inout Double?,
        latestCompletionPerModule: inout [String: Double]
    ) {
        if let nodeTitle = title, nodeTitle.hasPrefix("Test target "), let nodeStartTime = startTime {
            let moduleName = String(nodeTitle.dropFirst("Test target ".count))
            testTargetStartTimes[moduleName] = nodeStartTime

            if let current = earliestTestStart {
                earliestTestStart = min(current, nodeStartTime)
            } else {
                earliestTestStart = nodeStartTime
            }
        }

        if let emittedOutput = testDetails?.emittedOutput {
            parseSuiteCompletionTimestamps(
                from: emittedOutput,
                runnablePath: testDetails?.runnablePath,
                latestOverallCompletion: &latestOverallCompletion,
                latestCompletionPerModule: &latestCompletionPerModule
            )
        }

        if let subsections {
            for subsection in subsections {
                subsection.extractTestTimestampsRecursive(
                    testTargetStartTimes: &testTargetStartTimes,
                    earliestTestStart: &earliestTestStart,
                    latestOverallCompletion: &latestOverallCompletion,
                    latestCompletionPerModule: &latestCompletionPerModule
                )
            }
        }
    }

    private func parseSuiteCompletionTimestamps(
        from emittedOutput: String,
        runnablePath: String?,
        latestOverallCompletion: inout Double?,
        latestCompletionPerModule: inout [String: Double]
    ) {
        // Pattern: "Test Suite 'SuiteName' passed at 2025-11-24 18:39:44.625."
        let suiteCompletionPattern = #"Test Suite '[^']+' (?:passed|failed) at (\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})\.(\d+)"#

        guard let regex = try? NSRegularExpression(pattern: suiteCompletionPattern, options: []) else { return }

        let range = NSRange(emittedOutput.startIndex ..< emittedOutput.endIndex, in: emittedOutput)
        let matches = regex.matches(in: emittedOutput, options: [], range: range)

        for match in matches {
            guard let timestamp = parseTimestamp(from: match, in: emittedOutput) else { continue }

            updateLatestCompletion(&latestOverallCompletion, with: timestamp)
            updateModuleCompletion(
                emittedOutput: emittedOutput,
                runnablePath: runnablePath,
                timestamp: timestamp,
                latestCompletionPerModule: &latestCompletionPerModule
            )
        }
    }

    private func parseTimestamp(from match: NSTextCheckingResult, in text: String) -> Double? {
        guard match.numberOfRanges == 8,
              let yearRange = Range(match.range(at: 1), in: text),
              let monthRange = Range(match.range(at: 2), in: text),
              let dayRange = Range(match.range(at: 3), in: text),
              let hourRange = Range(match.range(at: 4), in: text),
              let minuteRange = Range(match.range(at: 5), in: text),
              let secondRange = Range(match.range(at: 6), in: text),
              let millisecondRange = Range(match.range(at: 7), in: text)
        else { return nil }

        let timeZone = TimeZone.current()
        var dateComponents = DateComponents()
        dateComponents.year = Int(text[yearRange]) ?? 0
        dateComponents.month = Int(text[monthRange]) ?? 0
        dateComponents.day = Int(text[dayRange]) ?? 0
        dateComponents.hour = Int(text[hourRange]) ?? 0
        dateComponents.minute = Int(text[minuteRange]) ?? 0
        dateComponents.second = Int(text[secondRange]) ?? 0
        dateComponents.nanosecond = (Int(text[millisecondRange]) ?? 0) * 1_000_000
        dateComponents.timeZone = timeZone

        var calendar = Calendar.current
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: dateComponents) else { return nil }

        return date.timeIntervalSince1970
    }

    private func updateLatestCompletion(_ latestCompletion: inout Double?, with timestamp: Double) {
        if let current = latestCompletion {
            latestCompletion = max(current, timestamp)
        } else {
            latestCompletion = timestamp
        }
    }

    private func updateModuleCompletion(
        emittedOutput: String,
        runnablePath: String?,
        timestamp: Double,
        latestCompletionPerModule: inout [String: Double]
    ) {
        guard let runnablePath,
              runnablePath.hasSuffix(".app") || runnablePath.hasSuffix(".xctest") || runnablePath.contains("/xctest")
        else { return }

        // Extract module name from XCTest pattern: "-[ModuleName.ClassName testMethod]"
        let xcTestPattern = #"-\[([^.]+)\."#
        guard let moduleRegex = try? NSRegularExpression(pattern: xcTestPattern, options: []),
              let moduleMatch = moduleRegex.firstMatch(
                  in: emittedOutput,
                  options: [],
                  range: NSRange(emittedOutput.startIndex ..< emittedOutput.endIndex, in: emittedOutput)
              ),
              let moduleRange = Range(moduleMatch.range(at: 1), in: emittedOutput)
        else { return }

        let moduleName = String(emittedOutput[moduleRange])
        guard !moduleName.isEmpty else { return }

        if let current = latestCompletionPerModule[moduleName] {
            latestCompletionPerModule[moduleName] = max(current, timestamp)
        } else {
            latestCompletionPerModule[moduleName] = timestamp
        }
    }

    /// Extract test failures from action logs
    /// Returns a mapping from test identifier (suiteName/testName) to failures
    func extractTestFailures(rootDirectory: AbsolutePath?) -> [String: [TestFailure]] {
        var failures: [String: [TestFailure]] = [:]
        extractTestFailuresRecursive(failures: &failures, rootDirectory: rootDirectory)
        return failures
    }

    private func extractTestFailuresRecursive(
        failures: inout [String: [TestFailure]],
        rootDirectory: AbsolutePath?
    ) {
        if let testDetails,
           let testName = testDetails.testName,
           let suiteName = testDetails.suiteName,
           let messages
        {
            let testIdentifier = "\(suiteName)/\(testName)"
            for message in messages {
                if let failure = parseFailureMessage(message, rootDirectory: rootDirectory) {
                    failures[testIdentifier, default: []].append(failure)
                }
            }
        }

        if let subsections {
            for subsection in subsections {
                subsection.extractTestFailuresRecursive(failures: &failures, rootDirectory: rootDirectory)
            }
        }
    }

    private func parseFailureMessage(
        _ message: Message,
        rootDirectory: AbsolutePath?
    ) -> TestFailure? {
        guard message.type == "test failure",
              let title = message.title ?? message.shortTitle
        else { return nil }

        let location = parseFileLocation(from: message.location?.url, rootDirectory: rootDirectory)
        return TestFailure(message: title, filePath: location.filePath, lineNumber: location.lineNumber)
    }

    private func parseFileLocation(
        from locationUrl: String?,
        rootDirectory: AbsolutePath?
    ) -> (filePath: RelativePath?, lineNumber: Int) {
        guard let locationUrl, locationUrl.hasPrefix("file://") else {
            return (nil, 0)
        }

        // URL format: file:///path/to/file.swift#EndingLineNumber=38&StartingLineNumber=38
        let urlString = locationUrl.replacingOccurrences(of: "file://", with: "")
        let components = urlString.components(separatedBy: "#")

        guard !components.isEmpty else { return (nil, 0) }

        let filePathString = components[0]
        let lineNumber = components.count >= 2 ? parseLineNumber(from: components[1]) : 0
        let filePath = parseRelativePath(from: filePathString, rootDirectory: rootDirectory)

        return (filePath, lineNumber)
    }

    private func parseLineNumber(from fragment: String) -> Int {
        let linePattern = #"StartingLineNumber=(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: linePattern, options: []),
              let match = regex.firstMatch(
                  in: fragment,
                  options: [],
                  range: NSRange(fragment.startIndex ..< fragment.endIndex, in: fragment)
              ),
              let lineRange = Range(match.range(at: 1), in: fragment)
        else { return 0 }

        return Int(fragment[lineRange]) ?? 0
    }

    private func parseRelativePath(from filePathString: String, rootDirectory: AbsolutePath?) -> RelativePath? {
        guard let absolutePath = try? AbsolutePath(validating: filePathString) else { return nil }
        return absolutePath.relative(to: rootDirectory ?? AbsolutePath.root)
    }
}
