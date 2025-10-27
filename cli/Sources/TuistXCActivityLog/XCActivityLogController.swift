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
    private let environment: Environmenting
    private let rootDirectoryLocator: RootDirectoryLocating
    private let gitController: GitControlling

    public init(
        fileSystem: FileSystem = FileSystem(),
        environment: Environmenting = Environment.current,
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
        gitController: GitControlling = GitController()
    ) {
        self.fileSystem = fileSystem
        self.environment = environment
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
                print("Set of steps for \(step.title): \(step.subSteps.map(\.title))")
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
            activityLog: activityLog,
            projectDerivedDataDirectory: path.removingLastComponent()
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
        let currentWorkingDirectory = try await environment.currentWorkingDirectory()
        let workingDirectory = environment.workspacePath ?? currentWorkingDirectory
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
            .serialCompactMap { step -> XCActivityBuildFile? in
                print("----")
                print(step.title)
                print(step.fetchedFromCache)
                print(step.notes)
                print(step.signature)
                print(step.buildIdentifier)
                print(step.domain)
                print(step.detailStepType)
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
        activityLog: XCLogParser.IDEActivityLog,
        projectDerivedDataDirectory: AbsolutePath
    ) async throws -> [CacheableTask] {
        var cacheableTasks: [CacheableTask] = []
        var keyStatuses: [String: (taskType: CacheableTask.TaskType, hasQuery: Bool, hasMaterialize: Bool, hasUpload: Bool)] = [:]
        
        // Parse the activity log into build steps
        let buildStep = try XCLogParser.ParserBuildSteps(
            omitWarningsDetails: true,
            omitNotesDetails: true,
            truncLargeIssues: false
        )
        .parse(activityLog: activityLog)
        
        // Get all flattened steps
        let allSteps = flattenedXCLogParserBuildStep([buildStep])
        
        // Analyze each step for cache operations
        for step in allSteps {
            if step.title.contains("Swift caching") || step.title.contains("Clang caching") {
                let isSwift = step.title.contains("Swift caching")
                let taskType: CacheableTask.TaskType = isSwift ? .swift : .clang
                
                // Extract key from title
                // For query/materialize: ["key"]
                // For upload: just the key without brackets
                var key: String? = nil
                
                if step.title.contains("query key") || step.title.contains("materialize key") {
                    // Extract key from ["key"] format
                    if let keyMatch = try? NSRegularExpression(pattern: "\\[\"([^\"]+)\"\\]")
                        .firstMatch(in: step.title, range: NSRange(location: 0, length: step.title.count)) {
                        let keyRange = Range(keyMatch.range(at: 1), in: step.title)!
                        key = String(step.title[keyRange])
                    }
                } else if step.title.contains("upload key") {
                    // Extract key after "upload key " (no brackets)
                    let pattern = "upload key ([^\\s]+)"
                    if let keyMatch = try? NSRegularExpression(pattern: pattern)
                        .firstMatch(in: step.title, range: NSRange(location: 0, length: step.title.count)) {
                        let keyRange = Range(keyMatch.range(at: 1), in: step.title)!
                        key = String(step.title[keyRange])
                    }
                }
                
                if let key = key {
                    var status = keyStatuses[key] ?? (taskType, false, false, false)
                    status.taskType = taskType
                    
                    if step.title.contains("query key") {
                        status.hasQuery = true
                    } else if step.title.contains("materialize key") {
                        status.hasMaterialize = true
                    } else if step.title.contains("upload key") {
                        status.hasUpload = true
                    }
                    
                    keyStatuses[key] = status
                }
            }
        }
        
        // Check if we need to verify local cache for ambiguous cases
        let compilationCachePath = projectDerivedDataDirectory.appending(component: "CompilationCache.noindex")
        
        // Determine cache status for each key
        for (key, status) in keyStatuses {
            let cacheStatus: CacheableTask.CacheStatus
            
            if status.hasUpload {
                // If there's an upload, it's definitely a miss
                cacheStatus = .miss
            } else if status.hasQuery && !status.hasMaterialize {
                // Query without materialize is a local hit
                cacheStatus = .localHit
            } else if status.hasQuery && status.hasMaterialize {
                // Query with materialize and no upload means it was a remote hit
                // (if there was no remote hit, it would have been uploaded)
                cacheStatus = .remoteHit
            } else {
                // Shouldn't happen, but default to miss
                continue
            }
            
            cacheableTasks.append(CacheableTask(
                key: key,
                status: cacheStatus,
                type: status.taskType
            ))
        }
        
        return cacheableTasks
    }
}

private struct TargetWithStep {
    let name: String
    let step: BuildStep
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
