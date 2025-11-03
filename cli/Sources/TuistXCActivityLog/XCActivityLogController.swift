import FileSystem
import Foundation
import Mockable
import Path
import TuistGit
import TuistRootDirectoryLocator
import TuistSupport
import XCLogParser

import struct TSCBasic.RegEx

@Mockable
public protocol XCActivityLogControlling {
    func mostRecentActivityLogFile(
        projectDerivedDataDirectory: AbsolutePath,
        filter: @escaping (XCActivityLogFile) -> Bool
    )
        async throws -> XCActivityLogFile?
    func buildTimesByTarget(projectDerivedDataDirectory: AbsolutePath) async throws -> [
        String: Double
    ]
    func buildTimesByTarget(activityLogPaths: [AbsolutePath]) async throws
        -> [String: Double]
    func parse(_ path: AbsolutePath) async throws -> XCActivityLog
}

extension XCActivityLogControlling {
    public func mostRecentActivityLogFile(
        projectDerivedDataDirectory: AbsolutePath
    ) async throws -> XCActivityLogFile? {
        return try await mostRecentActivityLogFile(
            projectDerivedDataDirectory: projectDerivedDataDirectory,
            filter: { _ in true }
        )
    }
}

// swiftlint:disable:next type_body_length
public struct XCActivityLogController: XCActivityLogControlling {
    private let fileSystem: FileSystem
    private let rootDirectoryLocator: RootDirectoryLocating
    private let gitController: GitControlling

    public init(
        fileSystem: FileSystem = FileSystem(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
        gitController: GitControlling = GitController()
    ) {
        self.fileSystem = fileSystem
        self.rootDirectoryLocator = rootDirectoryLocator
        self.gitController = gitController
    }

    public func buildTimesByTarget(projectDerivedDataDirectory: AbsolutePath) async throws
        -> [String: Double]
    {
        let buildLogsPath = projectDerivedDataDirectory.appending(components: [
            "Logs",
            "Build",
        ])
        let logStoreManifestPlistPath = buildLogsPath.appending(components: [
            "LogStoreManifest.plist",
        ])
        let logStoreManifest: XCLogStoreManifestPlist = try await fileSystem.readPlistFile(
            at: logStoreManifestPlistPath
        )

        let activityLogPaths = logStoreManifest.logs.keys.map {
            buildLogsPath.appending(components: ["\($0).xcactivitylog"])
        }

        return try await buildTimesByTarget(activityLogPaths: activityLogPaths)
    }

    public func buildTimesByTarget(activityLogPaths: [AbsolutePath]) async throws
        -> [String: Double]
    {
        var buildTimes: [String: Double] = [:]
        for activityLogPath in activityLogPaths {
            let activityLog = try XCLogParser.ActivityParser().parseActivityLogInURL(
                activityLogPath.url,
                redacted: false,
                withoutBuildSpecificInformation: false
            )
            let buildStep = try XCLogParser.ParserBuildSteps(
                omitWarningsDetails: true,
                omitNotesDetails: true,
                truncLargeIssues: true
            )
            .parse(activityLog: activityLog)

            for (targetName, targetBuildDuration) in flattenedXCLogParserBuildStep([buildStep])
                .filter({ $0.title.starts(with: "Build target") }).map({
                    ($0.signature, $0.subSteps.reduce(into: 0) { duration, subStep in
                        duration += subStep.compilationDuration * 1000 // From seconds to miliseconds
                    })
                })
            {
                // If a target supports multiple platforms, the time will persist is the time of the latest platform that we
                // built.
                buildTimes[targetName] = targetBuildDuration
            }
        }

        return buildTimes
    }

    private func flattenedXCLogParserBuildStep(_ buildSteps: [XCLogParser.BuildStep])
        -> [XCLogParser.BuildStep]
    {
        return buildSteps.flatMap { step in
            var flattened = [step]
            if !step.subSteps.isEmpty {
                flattened.append(contentsOf: flattenedXCLogParserBuildStep(step.subSteps))
            }
            return flattened
        }
    }

    public func mostRecentActivityLogFile(
        projectDerivedDataDirectory: AbsolutePath,
        filter: @escaping (XCActivityLogFile) -> Bool
    ) async throws -> XCActivityLogFile? {
        let logsBuildDirectoryPath = projectDerivedDataDirectory.appending(
            components: "Logs", "Build"
        )
        let logManifestPlistPath = logsBuildDirectoryPath.appending(
            components: "LogStoreManifest.plist"
        )
        guard try await fileSystem.exists(logManifestPlistPath) else { return nil }
        let plist: XCLogStoreManifestPlist = try await fileSystem.readPlistFile(
            at: logManifestPlistPath
        )

        let logFiles = plist.logs.values.map {
            XCActivityLogFile(
                path: logsBuildDirectoryPath.appending(component: $0.fileName),
                timeStoppedRecording: Date(timeIntervalSinceReferenceDate: $0.timeStoppedRecording),
                signature: $0.signature
            )
        }
        return logFiles.sorted(by: {
            $0.timeStoppedRecording > $1.timeStoppedRecording
        })
        .filter(filter)
        .first
    }

    public func parse(_ path: AbsolutePath) async throws -> XCActivityLog {
        let activityLog = try XCLogParser.ActivityParser().parseActivityLogInURL(
            path.url,
            redacted: false,
            withoutBuildSpecificInformation: false
        )

        let buildStep = try XCLogParser.ParserBuildSteps(
            omitWarningsDetails: false,
            omitNotesDetails: false,
            truncLargeIssues: false
        )
        .parse(activityLog: activityLog)

        let steps = flattenedXCLogParserBuildStep([buildStep])
        let targets = steps.filter { $0.type == .target }
            .filter { $0.title.contains("Build target ") }
            .map {
                TargetWithStep(
                    name: $0.title.replacingOccurrences(of: "Build target ", with: ""),
                    step: $0
                )
            }

        let category = buildCategory(
            steps: steps.filter {
                $0.type == .detail && $0.detailStepType != .swiftAggregatedCompilation
            },
            targets: targets
        )
        let rootDirectory = try await rootDirectory()

        let issues = try await issues(steps: steps, rootDirectory: rootDirectory)
            .uniqued()

        let files = try await files(steps: steps, rootDirectory: rootDirectory)

        let errorCount: Int = steps.reduce(0) { acc, step in
            let errors = step.errors ?? []

            return errors.filter { $0.severity == 2 }.count + acc
        }

        let cacheableTasks = try await analyzeCacheableTasks(
            buildSteps: steps,
            buildStartTime: activityLog.mainSection.timeStartedRecording
        )

        return XCActivityLog(
            version: activityLog.version,
            mainSection: XCActivityLogSection(
                uniqueIdentifier: activityLog.mainSection.uniqueIdentifier,
                timeStartedRecording: activityLog.mainSection.timeStartedRecording,
                timeStoppedRecording: activityLog.mainSection.timeStoppedRecording
            ),
            buildStep: XCActivityBuildStep(
                errorCount: errorCount
            ),
            category: category,
            issues: issues,
            files: files,
            targets: targets.map {
                let targetSteps = flattenedXCLogParserBuildStep([$0.step])
                return XCActivityTarget(
                    name: $0.name,
                    project: targetSteps.first(where: { $0.project() != "" })?.project() ?? "",
                    buildDuration: Int(($0.step.duration * 1000).rounded(.up)),
                    compilationDuration: Int(($0.step.compilationDuration * 1000).rounded(.up)),
                    status: targetSteps
                        .contains(where: { ($0.errors ?? []).contains(where: { $0.severity == 2 }) }) ? .failure : .success
                )
            },
            cacheableTasks: cacheableTasks
        )
    }

    private func rootDirectory() async throws -> AbsolutePath? {
        let currentWorkingDirectory = try await Environment.current.currentWorkingDirectory()
        let workingDirectory = Environment.current.workspacePath ?? currentWorkingDirectory
        if gitController.isInGitRepository(workingDirectory: workingDirectory) {
            return try gitController.topLevelGitDirectory(workingDirectory: workingDirectory)
        } else {
            return try await rootDirectoryLocator.locate(from: workingDirectory)
        }
    }

    private func files(
        steps: [BuildStep],
        rootDirectory: AbsolutePath?
    ) async throws
        -> [XCActivityBuildFile]
    {
        let derivedDataDirectory = try await Environment.current.derivedDataDirectory()
        return try await steps
            .filter { $0.type == .detail }
            .concurrentCompactMap { step -> XCActivityBuildFile? in
                let type: XCActivityBuildFileType
                switch step.detailStepType {
                case .swiftCompilation:
                    type = .swift
                case .cCompilation:
                    type = .c
                default:
                    if step.signature.hasPrefix("SwiftCompile ") {
                        type = .swift
                    } else {
                        return nil
                    }
                }

                // We want to ignore steps for emitting modules as we care about the compilation of the file itself.
                guard !step.title.hasPrefix("Emit") else {
                    return nil
                }

                if let absolutePath = try? AbsolutePath(
                    validating: step.documentURL
                        .replacingOccurrences(of: "file://", with: "")
                ), derivedDataDirectory.isAncestor(of: absolutePath) {
                    return nil
                }

                guard let path = try await path(of: step, rootDirectory: rootDirectory) else { return nil }

                return XCActivityBuildFile(
                    type: type,
                    target: step.target(),
                    project: step.project(),
                    path: path,
                    compilationDuration: Int((step.compilationDuration * 1000).rounded(.up))
                )
            }
    }

    private func issues(
        steps: [BuildStep],
        rootDirectory: AbsolutePath?
    ) async throws
        -> [XCActivityIssue]
    {
        return
            try await steps
                .compactMap { $0 }
                .concurrentMap { try await xcactivityIssues($0, rootDirectory: rootDirectory) }
                .flatMap { $0 }
    }

    private func xcactivityIssues(_ step: BuildStep, rootDirectory: AbsolutePath?) async throws -> [XCActivityIssue] {
        let path = try await path(of: step, rootDirectory: rootDirectory)
        let errors = step.errors ?? []
        let warnings = step.warnings ?? []
        return (errors + warnings).map { notice in
            let type: XCActivityIssueType = if notice.severity == 1 {
                .warning
            } else {
                .error
            }

            var message: String? = notice.detail
            if var noticeDetail = notice.detail {
                if let warningRange = noticeDetail.range(of: "warning: ") {
                    noticeDetail = String(noticeDetail[warningRange.upperBound...])
                }

                if let errorRange = noticeDetail.range(of: "error: ") {
                    noticeDetail = String(noticeDetail[errorRange.upperBound...])
                }

                if let suffixRange = noticeDetail.range(of: " ^~") {
                    noticeDetail = String(noticeDetail[..<suffixRange.lowerBound])
                }

                message = noticeDetail
            }

            return XCActivityIssue(
                type: type,
                target: step.target(),
                project: step.project(),
                title: step.title,
                signature: step.signature,
                stepType: XCActivityStepType(signature: step.signature),
                path: path,
                message: message,
                startingLine: Int(notice.startingLineNumber),
                endingLine: Int(notice.endingLineNumber),
                startingColumn: Int(notice.startingColumnNumber),
                endingColumn: Int(notice.endingColumnNumber)
            )
        }
    }

    private func buildCategory(steps: [BuildStep], targets: [TargetWithStep])
        -> XCActivityBuildCategory
    {
        let targetIdentifiers = targetIdentifiers(buildSteps: steps)
        var targetsCompiledCount = [String: Int]()

        for target in targets {
            targetsCompiledCount[target.step.identifier] = 0
        }

        let buildSteps =
            steps
                .filter {
                    $0.detailStepType != .other && $0.detailStepType != .scriptExecution
                        && $0.detailStepType != .copySwiftLibs
                }

        for step in buildSteps {
            if !step.fetchedFromCache {
                guard let targetIdentifier = targetIdentifiers[step.identifier] else { continue }
                targetsCompiledCount[targetIdentifier, default: 0] += 1
            }
        }

        var targetsCategory = [String: XCActivityBuildCategory]()
        for (target, filesCompiledCount) in targetsCompiledCount {
            // If the number of steps not fetched from cache in 0, it was an incremental or a noop build. We currently default to
            // incremental.
            // If the number of steps not fetched from cache is equal to the number of all steps in the target, it was a clean
            // build.
            // If anything in between, it was an incremental build.
            let targetFilesCount = buildSteps.filter { targetIdentifiers[$0.identifier] == target }
                .count
            switch filesCompiledCount {
            case 0:
                targetsCategory[target] = .incremental
            case targetFilesCount:
                targetsCategory[target] = .clean
            default:
                targetsCategory[target] = .incremental
            }
        }

        // If at least 50% of the targets are clean, we categorise the build as clean.
        if targetsCategory.values.filter({ $0 == .clean }).count > targets.count / 2 {
            return .clean
        } else {
            return .incremental
        }
    }

    private func targetIdentifiers(
        buildSteps: [BuildStep]
    ) -> [String: String] {
        let targetBuildSteps = buildSteps.filter { $0.type == .target }
            .filter { $0.title.contains("Build target ") }
        var targetIdentifiers = targetBuildSteps.reduce([String: String]()) {
            dictionary, target -> [String: String] in
            return dictionary.merging(zip([target.identifier], [target.identifier])) { _, new in new
            }
        }

        let steps = buildSteps.filter {
            $0.type == .detail && $0.detailStepType != .swiftAggregatedCompilation
        }

        for step in steps.filter({ $0.detailStepType != .swiftCompilation }) {
            targetIdentifiers[step.identifier] = step.parentIdentifier
        }

        let swiftAggregatedSteps = buildSteps.filter {
            $0.type == .detail
                && $0.detailStepType == .swiftAggregatedCompilation
        }

        let swiftAggregatedStepsIds = swiftAggregatedSteps.reduce([String: String]()) {
            dictionary, step -> [String: String] in
            return dictionary.merging(zip([step.identifier], [step.parentIdentifier])) { _, new in
                new
            }
        }

        for step
            in steps
            .filter({ $0.detailStepType == .swiftCompilation })
        {
            // A swift step can have either a target as a parent or a swiftAggregatedCompilation
            if targetIdentifiers[step.parentIdentifier] == nil {
                // If the parent is a swiftAggregatedCompilation we use the target id from that parent step
                if let swiftTargetId = swiftAggregatedStepsIds[step.parentIdentifier] {
                    targetIdentifiers[step.identifier] = swiftTargetId
                }
            } else {
                targetIdentifiers[step.identifier] = step.parentIdentifier
            }
        }

        return targetIdentifiers
    }

    private func path(of step: BuildStep, rootDirectory: AbsolutePath?) async throws -> RelativePath? {
        if let file = try? AbsolutePath(
            validating: step.documentURL
                .replacingOccurrences(of: "file://", with: "")
        ) {
            return file.relative(to: rootDirectory ?? AbsolutePath.root)
        } else {
            return nil
        }
    }

    private func analyzeCacheableTasks(
        buildSteps: [XCLogParser.BuildStep],
        buildStartTime: Double
    ) async throws -> [CacheableTask] {
        let cacheSteps = extractCacheSteps(from: buildSteps)
        let keyStatuses = aggregateKeyStatuses(from: cacheSteps)

        return try await determineCacheStatuses(
            keyStatuses: keyStatuses,
            buildStartTime: buildStartTime
        )
    }

    private func extractCacheSteps(from buildSteps: [XCLogParser.BuildStep]) -> [CacheStep] {
        return buildSteps.compactMap { step in
            guard step.title.contains("Swift caching") || step.title.contains("Clang caching") else {
                return nil
            }

            let taskType: CacheableTask.TaskType = step.title.contains("Swift caching") ? .swift : .clang

            guard let key = extractCacheKey(from: step.title),
                  let operation = determineCacheOperation(from: step.title)
            else {
                return nil
            }

            let isMiss = step.notes?.contains { $0.title == "cache key query miss" } ?? false

            return CacheStep(key: key, taskType: taskType, operation: operation, isMiss: isMiss)
        }
    }

    private func extractCacheKey(from title: String) -> String? {
        if title.contains("query key") || title.contains("materialize key") {
            // Extract key from ["key"] format
            let pattern = "\\[\"([^\"]+)\"\\]"
            return extractKeyWithPattern(pattern, from: title)
        } else if title.contains("upload key") {
            // Extract key after "upload key " (no brackets)
            let pattern = "upload key ([^\\s]+)"
            return extractKeyWithPattern(pattern, from: title)
        }
        return nil
    }

    private func extractKeyWithPattern(_ pattern: String, from title: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: title, range: NSRange(location: 0, length: title.count)),
              let keyRange = Range(match.range(at: 1), in: title)
        else {
            return nil
        }
        return String(title[keyRange])
    }

    private func determineCacheOperation(from title: String) -> CacheOperation? {
        if title.contains("query key") {
            return .query
        } else if title.contains("materialize key") {
            return .materialize
        } else if title.contains("upload key") {
            return .upload
        }
        return nil
    }

    private func aggregateKeyStatuses(from cacheSteps: [CacheStep]) -> [String: CacheKeyStatus] {
        var keyStatuses: [String: CacheKeyStatus] = [:]

        for step in cacheSteps {
            var status = keyStatuses[step.key] ?? CacheKeyStatus(taskType: step.taskType)
            status.taskType = step.taskType

            switch step.operation {
            case .query:
                status.hasQuery = true
            case .materialize:
                status.hasMaterialize = true
            case .upload:
                break // No longer tracking uploads
            }

            if step.isMiss {
                status.isMiss = true
            }

            keyStatuses[step.key] = status
        }

        return keyStatuses
    }

    private func determineCacheStatuses(
        keyStatuses: [String: CacheKeyStatus],
        buildStartTime _: Double
    ) async throws -> [CacheableTask] {
        return try await keyStatuses.concurrentMap { key, status in
            let cacheStatus = try await determineCacheStatus(
                for: status
            )

            return CacheableTask(
                key: key,
                status: cacheStatus,
                type: status.taskType
            )
        }
    }

    private func determineCacheStatus(
        for status: CacheKeyStatus,
    ) async throws -> CacheableTask.CacheStatus {
        if status.isMiss {
            return .miss
        } else {
            if status.hasQuery {
                return .remoteHit
            } else {
                return .localHit
            }
        }
    }
}

private struct TargetWithStep {
    let name: String
    let step: BuildStep
}

private struct CacheStep {
    let key: String
    let taskType: CacheableTask.TaskType
    let operation: CacheOperation
    let isMiss: Bool
}

private enum CacheOperation {
    case query
    case materialize
    case upload
}

private struct CacheKeyStatus {
    var taskType: CacheableTask.TaskType
    var hasQuery: Bool = false
    var hasMaterialize: Bool = false
    var isMiss: Bool = false

    init(taskType: CacheableTask.TaskType) {
        self.taskType = taskType
    }
}

extension BuildStep {
    fileprivate func target() -> String {
        (
            try? RegEx(pattern: "in target '([^']+)'").matchGroups(in: signature)
                .first?.first
        )?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    fileprivate func project() -> String {
        (
            try? RegEx(pattern: "from project '([^']+)'").matchGroups(in: signature)
                .first?.first
        )?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}
