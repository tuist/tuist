import Foundation
import Path

// MARK: - XCResult Test Output Models

struct XCResultTestOutput: Codable {
    let devices: [Device]?
    let testNodes: [TestNode]
    let testPlanConfigurations: [TestPlanConfiguration]?
}

struct Device: Codable {
    let architecture: String?
    let deviceId: String?
    let deviceName: String?
    let modelName: String?
    let osBuildNumber: String?
    let osVersion: String?
    let platform: String?
}

struct TestNode: Codable {
    let children: [TestNode]?
    let name: String?
    let nodeIdentifier: String?
    let nodeIdentifierURL: String?
    let nodeType: String?
    let result: String?
    let duration: String?
    let durationInSeconds: Double?
}

struct TestPlanConfiguration: Codable {
    let configurationId: String?
    let configurationName: String?
}

// MARK: - Action Log Models

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

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Try to decode emittedOutput, but if it fails, use nil
            emittedOutput = try? container.decodeIfPresent(String.self, forKey: .emittedOutput)
        }

        private enum CodingKeys: String, CodingKey {
            case emittedOutput
        }
    }

    struct TestDetails: Codable {
        let emittedOutput: String?
        let runnablePath: String?
        let testName: String?
        let suiteName: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Try to decode emittedOutput, but if it fails, use nil
            emittedOutput = try? container.decodeIfPresent(String.self, forKey: .emittedOutput)
            runnablePath = try container.decodeIfPresent(String.self, forKey: .runnablePath)
            testName = try container.decodeIfPresent(String.self, forKey: .testName)
            suiteName = try container.decodeIfPresent(String.self, forKey: .suiteName)
        }

        private enum CodingKeys: String, CodingKey {
            case emittedOutput
            case runnablePath
            case testName
            case suiteName
        }
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
}

/// Helper to recursively search for emittedOutput
extension ActionLogSection {
    func collectEmittedOutputs() -> [String] {
        var outputs: [String] = []

        // Collect from commandInvocationDetails
        if let emittedOutput = commandInvocationDetails?.emittedOutput, !emittedOutput.isEmpty {
            outputs.append(emittedOutput)
        }

        // Collect from testDetails
        if let emittedOutput = testDetails?.emittedOutput, !emittedOutput.isEmpty {
            outputs.append(emittedOutput)
        }

        // Recursively collect from subsections
        if let subsections {
            for subsection in subsections {
                outputs.append(contentsOf: subsection.collectEmittedOutputs())
            }
        }

        return outputs
    }

    /// Extract test target start times and suite completion timestamps
    /// Returns start times per module, earliest overall start, and latest completion timestamps
    func extractTestTimestamps() -> (
        testTargetStartTimes: [String: Double],
        earliestTestStart: Double?,
        latestOverallCompletion: Double?,
        latestCompletionPerModule: [String: Double]
    ) {
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

        return (testTargetStartTimes, earliestTestStart, latestOverallCompletion, latestCompletionPerModule)
    }

    private func extractTestTimestampsRecursive(
        testTargetStartTimes: inout [String: Double],
        earliestTestStart: inout Double?,
        latestOverallCompletion: inout Double?,
        latestCompletionPerModule: inout [String: Double]
    ) {
        // Check if this is a "Test target" node
        if let nodeTitle = title, nodeTitle.hasPrefix("Test target "), let nodeStartTime = startTime {
            // Extract module name from "Test target ModuleName"
            let moduleName = String(nodeTitle.dropFirst("Test target ".count))

            // Store the test target start time
            testTargetStartTimes[moduleName] = nodeStartTime

            // Update earliest test start
            if let current = earliestTestStart {
                earliestTestStart = min(current, nodeStartTime)
            } else {
                earliestTestStart = nodeStartTime
            }
        }

        // Pattern: "Test Suite 'SuiteName' passed at 2025-11-24 18:39:44.625."
        let suiteCompletionPattern = #"Test Suite '[^']+' (?:passed|failed) at (\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})\.(\d+)"#

        // Check emittedOutput from both testDetails and commandInvocationDetails
        let emittedOutputs = [testDetails?.emittedOutput, commandInvocationDetails?.emittedOutput].compactMap { $0 }

        for emittedOutput in emittedOutputs {
            guard let regex = try? NSRegularExpression(pattern: suiteCompletionPattern, options: []) else { continue }

            let range = NSRange(emittedOutput.startIndex ..< emittedOutput.endIndex, in: emittedOutput)
            let matches = regex.matches(in: emittedOutput, options: [], range: range)

            for match in matches {
                // Extract timestamp components
                guard match.numberOfRanges == 8,
                      let yearRange = Range(match.range(at: 1), in: emittedOutput),
                      let monthRange = Range(match.range(at: 2), in: emittedOutput),
                      let dayRange = Range(match.range(at: 3), in: emittedOutput),
                      let hourRange = Range(match.range(at: 4), in: emittedOutput),
                      let minuteRange = Range(match.range(at: 5), in: emittedOutput),
                      let secondRange = Range(match.range(at: 6), in: emittedOutput),
                      let millisecondRange = Range(match.range(at: 7), in: emittedOutput)
                else { continue }

                let year = Int(emittedOutput[yearRange]) ?? 0
                let month = Int(emittedOutput[monthRange]) ?? 0
                let day = Int(emittedOutput[dayRange]) ?? 0
                let hour = Int(emittedOutput[hourRange]) ?? 0
                let minute = Int(emittedOutput[minuteRange]) ?? 0
                let second = Int(emittedOutput[secondRange]) ?? 0
                let millisecond = Int(emittedOutput[millisecondRange]) ?? 0

                // Convert to Unix timestamp
                // The timestamps in the log appear to be in local time, so we use the current timezone
                var dateComponents = DateComponents()
                dateComponents.year = year
                dateComponents.month = month
                dateComponents.day = day
                dateComponents.hour = hour
                dateComponents.minute = minute
                dateComponents.second = second
                dateComponents.nanosecond = millisecond * 1_000_000
                dateComponents.timeZone = TimeZone.current

                var calendar = Calendar.current
                calendar.timeZone = TimeZone.current
                guard let date = calendar.date(from: dateComponents) else { continue }
                let timestamp = date.timeIntervalSince1970

                // Update overall latest timestamp
                if let current = latestOverallCompletion {
                    latestOverallCompletion = max(current, timestamp)
                } else {
                    latestOverallCompletion = timestamp
                }

                // Update per-module timestamp if this section has a module
                if let runnablePath = testDetails?.runnablePath,
                   runnablePath.hasSuffix(".app") || runnablePath.hasSuffix(".xctest") || runnablePath.contains("/xctest")
                {
                    // Extract module name from XCTest pattern: "-[ModuleName.ClassName testMethod]"
                    let xcTestPattern = #"-\[([^.]+)\."#
                    if let moduleRegex = try? NSRegularExpression(pattern: xcTestPattern, options: []),
                       let moduleMatch = moduleRegex.firstMatch(
                           in: emittedOutput,
                           options: [],
                           range: NSRange(emittedOutput.startIndex ..< emittedOutput.endIndex, in: emittedOutput)
                       ),
                       let moduleRange = Range(moduleMatch.range(at: 1), in: emittedOutput)
                    {
                        let moduleName = String(emittedOutput[moduleRange])
                        if !moduleName.isEmpty {
                            if let current = latestCompletionPerModule[moduleName] {
                                latestCompletionPerModule[moduleName] = max(current, timestamp)
                            } else {
                                latestCompletionPerModule[moduleName] = timestamp
                            }
                        }
                    }
                }
            }
        }

        // Recursively process subsections
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

    /// Extract test failures from action logs
    /// Returns a mapping from test identifier (suiteName/testName) to failures
    func extractTestFailures(rootDirectory: AbsolutePath?) -> [String: [(
        message: String,
        filePath: RelativePath?,
        lineNumber: Int
    )]] {
        var failures: [String: [(message: String, filePath: RelativePath?, lineNumber: Int)]] = [:]
        extractTestFailuresRecursive(failures: &failures, rootDirectory: rootDirectory)
        return failures
    }

    private func extractTestFailuresRecursive(
        failures: inout [String: [(message: String, filePath: RelativePath?, lineNumber: Int)]],
        rootDirectory: AbsolutePath?
    ) {
        // Check if this section has test details and failure messages
        if let testDetails,
           let testName = testDetails.testName,
           let suiteName = testDetails.suiteName,
           let messages
        {
            for message in messages {
                // Only process test failure messages
                guard message.type == "test failure",
                      let title = message.title ?? message.shortTitle
                else {
                    continue
                }

                // Parse the location URL to extract file path and line number
                var filePath: RelativePath?
                var lineNumber = 0

                if let locationUrl = message.location?.url,
                   locationUrl.hasPrefix("file://")
                {
                    // URL format: file:///path/to/file.swift#EndingLineNumber=38&StartingLineNumber=38
                    let urlString = locationUrl.replacingOccurrences(of: "file://", with: "")
                    let components = urlString.components(separatedBy: "#")

                    if components.count >= 1 {
                        let filePathString = components[0]

                        // Parse line number from URL fragment
                        if components.count >= 2 {
                            let fragment = components[1]
                            // Extract StartingLineNumber parameter
                            let linePattern = #"StartingLineNumber=(\d+)"#
                            if let regex = try? NSRegularExpression(pattern: linePattern, options: []),
                               let match = regex.firstMatch(
                                   in: fragment,
                                   options: [],
                                   range: NSRange(fragment.startIndex ..< fragment.endIndex, in: fragment)
                               ),
                               let lineRange = Range(match.range(at: 1), in: fragment)
                            {
                                lineNumber = Int(fragment[lineRange]) ?? 0
                            }
                        }

                        // Convert file path to RelativePath
                        if let absolutePath = try? AbsolutePath(validating: filePathString) {
                            filePath = absolutePath.relative(to: rootDirectory ?? AbsolutePath.root)
                        }
                    }
                }

                // Create test identifier
                let testIdentifier = "\(suiteName)/\(testName)"

                // Add failure to the list
                if failures[testIdentifier] == nil {
                    failures[testIdentifier] = []
                }
                failures[testIdentifier]?.append((message: title, filePath: filePath, lineNumber: lineNumber))
            }
        }

        // Recursively process subsections
        if let subsections {
            for subsection in subsections {
                subsection.extractTestFailuresRecursive(failures: &failures, rootDirectory: rootDirectory)
            }
        }
    }
}
