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

    struct TestDurations {
        let overallDuration: Int?
        let moduleDurations: [String: Int]
    }

    /// Extract test durations from the action log's structural timing (epoch-based startTime/duration).
    /// This includes the full test execution time, accounting for retries when -retry-tests-on-failure is used.
    func extractTestDurations() -> TestDurations {
        var earliestTestStart: Double?
        var launchActionsEnd: Double?
        var moduleDurations: [String: Int] = [:]

        for subsection in subsections ?? [] {
            guard let subTitle = subsection.title else { continue }

            if subTitle.hasPrefix("Test target "), let nodeStartTime = subsection.startTime {
                if let current = earliestTestStart {
                    earliestTestStart = min(current, nodeStartTime)
                } else {
                    earliestTestStart = nodeStartTime
                }
            }

            if subTitle == "Launch actions" {
                if let start = subsection.startTime, let duration = subsection.duration {
                    launchActionsEnd = start + duration
                }
                for launchSub in subsection.subsections ?? [] {
                    guard let launchTitle = launchSub.title,
                          launchTitle.hasPrefix("Launch "),
                          let duration = launchSub.duration
                    else { continue }
                    let moduleName = String(launchTitle.dropFirst("Launch ".count))
                    let durationMs = Int(duration * 1000)
                    moduleDurations[moduleName] = durationMs
                }
            }
        }

        var overallDuration: Int?
        if let testStart = earliestTestStart, let end = launchActionsEnd {
            let durationSeconds = end - testStart
            if durationSeconds > 0 {
                overallDuration = Int(durationSeconds * 1000)
            }
        }

        return TestDurations(
            overallDuration: overallDuration,
            moduleDurations: moduleDurations
        )
    }

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
