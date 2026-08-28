import Foundation

struct BazelBuildMetricsTelemetry: Sendable, Equatable {
    let cpuTimeMilliseconds: Int
    let actionsExecuted: Int
    let targetsLoaded: Int
    let targetsConfigured: Int
    let packagesLoaded: Int

    static let empty = Self(
        cpuTimeMilliseconds: 0,
        actionsExecuted: 0,
        targetsLoaded: 0,
        targetsConfigured: 0,
        packagesLoaded: 0
    )
}

struct BazelInvocationTelemetry: Sendable, Equatable {
    let invocationID: String
    let command: String
    let status: String
    let exitCode: Int
    let startedAt: Date
    let finishedAt: Date
    let targetPatterns: [String]
    let requestedCommand: String
    let originalCommandLine: [String]
    let canonicalCommandLine: [String]
    let bazelVersion: String
    let gitBranch: String?
    let gitCommitSHA: String?
    let configurations: [String]
    let compilationMode: String
    let remoteCacheEnabled: Bool
    let remoteExecutionEnabled: Bool
    let clientPlatform: String
    let buildMetrics: BazelBuildMetricsTelemetry
}

struct BazelTestResultTelemetry: Sendable, Equatable {
    let invocationID: String
    let targetLabel: String
    let status: String
    let durationMilliseconds: Int
    let attemptCount: Int
    let finishedAt: Date
}

struct BazelBuildEventParseResult: Sendable, Equatable {
    let invocation: BazelInvocationTelemetry
    let testResults: [BazelTestResultTelemetry]
}

struct BazelBuildEventParser {
    func parse(
        data: Data,
        invocationID: String,
        startedAt fallbackStartedAt: Date,
        command fallbackCommand: String,
        requestedCommand fallbackRequestedCommand: String,
        finishedAt fallbackFinishedAt: Date,
        succeeded fallbackSucceeded: Bool,
        gitBranch: String? = nil,
        gitCommitSHA: String? = nil,
        clientPlatform: String = "unknown"
    ) -> BazelBuildEventParseResult? {
        var startedAt = fallbackStartedAt
        var finishedAt = fallbackFinishedAt
        var command = fallbackCommand
        var originalCommandLine: [String] = []
        var canonicalCommandLine: [String] = []
        var bazelVersion = ""
        var targetPatterns: [String] = []
        var configurations: [String] = []
        var compilationMode = ""
        var remoteCacheEnabled = false
        var remoteExecutionEnabled = false
        var buildMetrics = BazelBuildMetricsTelemetry.empty
        var exitCode = fallbackSucceeded ? 0 : 1
        var succeeded = fallbackSucceeded
        var testResults: [BazelTestResultTelemetry] = []
        var hasBuildEvent = false

        for event in events(from: data) {
            if let structuredCommandLine = dictionary(event["structuredCommandLine"]),
               let label = nonEmptyString(structuredCommandLine["commandLineLabel"])
            {
                switch label {
                case "original":
                    originalCommandLine = BazelCommandLineRedactor.structuredCommandLine(structuredCommandLine)
                case "canonical":
                    canonicalCommandLine = BazelCommandLineRedactor.structuredCommandLine(structuredCommandLine)
                default:
                    break
                }
            }

            if let started = dictionary(event["started"]) {
                hasBuildEvent = true
                command = nonEmptyString(started["command"]) ?? command
                bazelVersion = safeBazelVersion(started["buildToolVersion"])
                startedAt = timestamp(started["startTime"], fallback: timestamp(started["startTimeMillis"], fallback: startedAt))
            }

            if let options = dictionary(event["optionsParsed"]), let commandLine = strings(options["cmdLine"]) {
                let configuration = commandConfiguration(from: commandLine)
                configurations = configuration.configurations
                compilationMode = configuration.compilationMode
                remoteCacheEnabled = configuration.remoteCacheEnabled
                remoteExecutionEnabled = configuration.remoteExecutionEnabled
            }

            if let metrics = dictionary(event["buildMetrics"]) {
                buildMetrics = buildMetrics(from: metrics)
            }

            if let pattern = dictionary(dictionary(event["id"])?["pattern"]) {
                appendTargetPatterns(strings(pattern["pattern"]) ?? [], to: &targetPatterns)
            }

            if let testSummary = dictionary(event["testSummary"]),
               let testSummaryID = dictionary(dictionary(event["id"])?["testSummary"]),
               let targetLabel = nonEmptyString(testSummaryID["label"])
            {
                let status = testStatus(testSummary["overallStatus"])
                let durationMilliseconds = durationMilliseconds(
                    testSummary["totalRunDuration"],
                    fallback: integer(testSummary["totalRunDurationMillis"]) ?? 0
                )
                let testFinishedAt = timestamp(
                    testSummary["lastStopTime"],
                    fallback: timestamp(testSummary["lastStopTimeMillis"], fallback: finishedAt)
                )
                let attemptCount = max(integer(testSummary["attemptCount"]) ?? 1, 1)

                testResults.append(
                    BazelTestResultTelemetry(
                        invocationID: invocationID,
                        targetLabel: targetLabel,
                        status: status,
                        durationMilliseconds: max(durationMilliseconds, 0),
                        attemptCount: attemptCount,
                        finishedAt: testFinishedAt
                    )
                )
            }

            if let finished = dictionary(event["finished"]) {
                hasBuildEvent = true
                finishedAt = timestamp(
                    finished["finishTime"],
                    fallback: timestamp(finished["finishTimeMillis"], fallback: finishedAt)
                )
                exitCode = integer(dictionary(finished["exitCode"])?["code"]) ?? exitCode
                succeeded = boolean(finished["overallSuccess"]) ?? (exitCode == 0)
            }
        }

        guard hasBuildEvent, !command.isEmpty else { return nil }

        return BazelBuildEventParseResult(
            invocation: BazelInvocationTelemetry(
                invocationID: invocationID,
                command: command,
                status: succeeded && exitCode == 0 ? "success" : "failure",
                exitCode: exitCode,
                startedAt: startedAt,
                finishedAt: max(finishedAt, startedAt),
                targetPatterns: targetPatterns,
                requestedCommand: fallbackRequestedCommand,
                originalCommandLine: originalCommandLine,
                canonicalCommandLine: canonicalCommandLine,
                bazelVersion: bazelVersion,
                gitBranch: gitBranch,
                gitCommitSHA: gitCommitSHA,
                configurations: configurations,
                compilationMode: compilationMode,
                remoteCacheEnabled: remoteCacheEnabled,
                remoteExecutionEnabled: remoteExecutionEnabled,
                clientPlatform: clientPlatform,
                buildMetrics: buildMetrics
            ),
            testResults: testResults
        )
    }

    private func events(from data: Data) -> [[String: Any]] {
        let eventLines: [[String: Any]] = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> [String: Any]? in
                guard let eventData = line.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any]
                else {
                    return nil
                }
                return event
            }

        if !eventLines.isEmpty {
            return eventLines
        }

        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private func commandConfiguration(from commandLine: [String]) -> (
        configurations: [String],
        compilationMode: String,
        remoteCacheEnabled: Bool,
        remoteExecutionEnabled: Bool
    ) {
        var configurations: [String] = []
        var compilationMode = ""
        var remoteCacheEnabled = false
        var remoteExecutionEnabled = false
        var nextOption: String?

        for option in commandLine {
            if let currentOption = nextOption {
                apply(
                    option: currentOption,
                    value: option,
                    configurations: &configurations,
                    compilationMode: &compilationMode,
                    remoteCacheEnabled: &remoteCacheEnabled,
                    remoteExecutionEnabled: &remoteExecutionEnabled
                )
                nextOption = nil
            } else if let (optionName, value) = option.splitOnce(separator: "=") {
                apply(
                    option: String(optionName),
                    value: String(value),
                    configurations: &configurations,
                    compilationMode: &compilationMode,
                    remoteCacheEnabled: &remoteCacheEnabled,
                    remoteExecutionEnabled: &remoteExecutionEnabled
                )
            } else if ["--config", "--compilation_mode", "--remote_cache", "--remote_executor"].contains(option) {
                nextOption = option
            }
        }

        return (configurations, compilationMode, remoteCacheEnabled, remoteExecutionEnabled)
    }

    private func apply(
        option: String,
        value: String,
        configurations: inout [String],
        compilationMode: inout String,
        remoteCacheEnabled: inout Bool,
        remoteExecutionEnabled: inout Bool
    ) {
        switch option {
        case "--config" where isSafeConfiguration(value):
            if configurations.count < 20, !configurations.contains(value) {
                configurations.append(value)
            }
        case "--compilation_mode" where ["dbg", "fastbuild", "opt"].contains(value):
            compilationMode = value
        case "--remote_cache" where !value.isEmpty:
            remoteCacheEnabled = true
        case "--remote_executor" where !value.isEmpty:
            remoteExecutionEnabled = true
        default:
            break
        }
    }

    private func appendTargetPatterns(_ patterns: [String], to targetPatterns: inout [String]) {
        for pattern in patterns {
            let pattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pattern.isEmpty, pattern.utf8.count <= 1024, targetPatterns.count < 100, !targetPatterns.contains(pattern) {
                targetPatterns.append(pattern)
            }
        }
    }

    private func buildMetrics(from metrics: [String: Any]) -> BazelBuildMetricsTelemetry {
        let actionSummary = dictionary(metrics["actionSummary"])
        let targetMetrics = dictionary(metrics["targetMetrics"])
        let packageMetrics = dictionary(metrics["packageMetrics"])
        let timingMetrics = dictionary(metrics["timingMetrics"])

        return BazelBuildMetricsTelemetry(
            cpuTimeMilliseconds: nonNegativeInteger(timingMetrics?["cpuTimeInMs"]),
            actionsExecuted: nonNegativeInteger(actionSummary?["actionsExecuted"]),
            targetsLoaded: nonNegativeInteger(targetMetrics?["targetsLoaded"]),
            targetsConfigured: nonNegativeInteger(targetMetrics?["targetsConfigured"]),
            packagesLoaded: nonNegativeInteger(packageMetrics?["packagesLoaded"])
        )
    }

    private func testStatus(_ value: Any?) -> String {
        switch string(value)?.uppercased() ?? String(integer(value) ?? -1) {
        case "PASSED", "1": return "success"
        case "FLAKY", "2": return "flaky"
        case "NO_STATUS", "SKIPPED", "0", "5", "8": return "skipped"
        default: return "failure"
        }
    }

    private func durationMilliseconds(_ value: Any?, fallback: Int) -> Int {
        guard let duration = string(value), duration.hasSuffix("s") else { return fallback }
        return Int((Double(duration.dropLast()) ?? 0) * 1000)
    }

    private func timestamp(_ value: Any?, fallback: Date) -> Date {
        if let milliseconds = integer(value) {
            return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
        }

        if let value = string(value), let date = ISO8601DateFormatter().date(from: value) {
            return date
        }

        if let timestamp = dictionary(value), let seconds = integer(timestamp["seconds"]) {
            let nanos = integer(timestamp["nanos"]) ?? 0
            return Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanos) / 1_000_000_000)
        }

        return fallback
    }

    private func isSafeConfiguration(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || "_-./".contains($0))
        }
    }

    private func safeBazelVersion(_ value: Any?) -> String {
        guard let value = string(value)?.trimmingCharacters(in: .whitespacesAndNewlines), value.utf8.count <= 128,
              value.allSatisfy({ $0.isASCII && (!$0.isWhitespace || $0 == " ") })
        else {
            return ""
        }
        return value
    }

    private func dictionary(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
    private func strings(_ value: Any?) -> [String]? { value as? [String] }
    private func string(_ value: Any?) -> String? {
        switch value {
        case let value as String: value
        case let value as NSNumber: value.stringValue
        default: nil
        }
    }

    private func boolean(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool: value
        case let value as NSNumber: value.boolValue
        default: nil
        }
    }

    private func integer(_ value: Any?) -> Int? {
        switch value {
        case let value as Int: value
        case let value as NSNumber: value.intValue
        case let value as String: Int(value)
        default: nil
        }
    }

    private func nonNegativeInteger(_ value: Any?) -> Int {
        max(integer(value) ?? 0, 0)
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let value = string(value)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

enum BazelCommandLineRedactor {
    private static let maximumArguments = 500
    private static let maximumArgumentLength = 2048
    private static let omittedOptions: Set<String> = ["client_env"]
    private static let redactedOptionFragments = [
        "auth", "bazelrc", "binary_path", "build_event", "client_cwd", "cookie", "credential", "failure_detail",
        "header", "host_jvm_args", "install_base", "install_md5", "key", "output_base", "output_user_root", "password",
        "private", "profile", "proxy", "rc_source", "repo_env", "repository_cache", "sandbox_base", "secret", "token",
        "workspace_directory",
    ]

    static func requestedCommand(arguments: [String]) -> String {
        (["bazel"] + sanitizedArguments(arguments)).map(shellQuoted).joined(separator: " ")
    }

    static func structuredCommandLine(_ structuredCommandLine: [String: Any]) -> [String] {
        let arguments = sections(from: structuredCommandLine).flatMap { section -> [String] in
            let chunks = strings(dictionary(section["chunkList"])?["chunk"]) ?? []
            let optionValues = Self.options(from: section).compactMap { option -> String? in
                let name = string(option["optionName"])
                let form = string(option["combinedForm"]) ?? name.map { "--\($0)" }
                return form.flatMap { sanitizedArgument($0, optionName: name) }
            }
            return sanitizedArguments(chunks) + optionValues
        }

        return Array(arguments.prefix(maximumArguments))
    }

    private static func sections(from structuredCommandLine: [String: Any]) -> [[String: Any]] {
        structuredCommandLine["sections"] as? [[String: Any]] ?? []
    }

    private static func options(from section: [String: Any]) -> [[String: Any]] {
        dictionary(section["optionList"])?["option"] as? [[String: Any]] ?? []
    }

    private static func sanitizedArguments(_ arguments: [String]) -> [String] {
        var sanitized: [String] = []
        var omitNextArgument = false
        var redactNextArgument = false

        for argument in arguments {
            guard let argument = bounded(argument) else { continue }

            if omitNextArgument {
                omitNextArgument = false
                continue
            }

            if redactNextArgument {
                sanitized.append("<REDACTED>")
                redactNextArgument = false
                continue
            }

            guard let optionName = optionName(from: argument) else {
                sanitized.append(argument)
                continue
            }

            if omittedOptions.contains(optionName) {
                omitNextArgument = !argument.contains("=")
                continue
            }

            if shouldRedact(optionName) {
                sanitized.append(redactedOption(optionName))
                redactNextArgument = !argument.contains("=")
                continue
            }

            sanitized.append(argument)
        }

        return Array(sanitized.prefix(maximumArguments))
    }

    private static func sanitizedArgument(_ argument: String, optionName: String?) -> String? {
        guard let argument = bounded(argument) else { return nil }
        let optionName = optionName.map(normalizedOptionName) ?? self.optionName(from: argument)

        guard let optionName else { return argument }
        if omittedOptions.contains(optionName) { return nil }
        if shouldRedact(optionName) { return redactedOption(optionName) }
        return argument
    }

    private static func optionName(from argument: String) -> String? {
        guard argument.hasPrefix("--") else { return nil }
        let name = argument.dropFirst(2).prefix { $0 != "=" && !$0.isWhitespace }
        guard !name.isEmpty else { return nil }
        return normalizedOptionName(String(name))
    }

    private static func normalizedOptionName(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "-")).lowercased()
    }

    private static func shouldRedact(_ optionName: String) -> Bool {
        redactedOptionFragments.contains { optionName.contains($0) }
    }

    private static func redactedOption(_ optionName: String) -> String {
        "--\(optionName)=<REDACTED>"
    }

    private static func bounded(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.utf8.count <= maximumArgumentLength,
              value.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F })
        else {
            return nil
        }
        return value
    }

    private static func shellQuoted(_ value: String) -> String {
        guard value.contains(where: { $0.isWhitespace || "'\\\"$`".contains($0) }) else { return value }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'"))'"
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
    private static func strings(_ value: Any?) -> [String]? { value as? [String] }
    private static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String: value
        case let value as NSNumber: value.stringValue
        default: nil
        }
    }
}

extension String {
    fileprivate func splitOnce(separator: Character) -> (Substring, Substring)? {
        guard let index = firstIndex(of: separator) else { return nil }
        return (self[..<index], self[self.index(after: index)...])
    }
}
