import FileSystem
import Foundation
import Mockable
import Path
import TuistRootDirectoryLocator
import TuistSupport
import XCLogParser

import struct TSCBasic.RegEx

@Mockable
public protocol XCActivityLogControlling {
    func mostRecentActivityLogPath(projectDerivedDataDirectory: AbsolutePath, after: Date)
        async throws -> AbsolutePath?
    func buildTimesByTarget(projectDerivedDataDirectory: AbsolutePath) async throws -> [
        String: Double
    ]
    func buildTimesByTarget(activityLogPaths: [AbsolutePath]) async throws
        -> [String: Double]
    func parse(_ path: AbsolutePath) async throws -> XCActivityLog
}

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
                    ($0.signature, $0.duration)
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

    public func mostRecentActivityLogPath(projectDerivedDataDirectory: AbsolutePath, after: Date)
        async throws -> AbsolutePath?
    {
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

        guard let latestLog = plist.logs.values.sorted(by: {
            $0.timeStoppedRecording > $1.timeStoppedRecording
        }).first,
            environment
            .workspacePath == nil
            || (
                after.timeIntervalSinceReferenceDate - 10 ..< after.timeIntervalSinceReferenceDate
                    + 10
            ) ~= latestLog.timeStoppedRecording
        else {
            return nil
        }
        return logsBuildDirectoryPath.appending(component: latestLog.fileName)
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

        return XCActivityLog(
            version: activityLog.version,
            mainSection: XCActivityLogSection(
                uniqueIdentifier: activityLog.mainSection.uniqueIdentifier,
                timeStartedRecording: activityLog.mainSection.timeStartedRecording,
                timeStoppedRecording: activityLog.mainSection.timeStoppedRecording
            ),
            buildStep: XCActivityBuildStep(
                errorCount: buildStep.errorCount
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
                    status: targetSteps.allSatisfy { $0.errorCount == 0 } ? .success : .failure
                )
            }
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
        try await steps
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
                ), try await Environment.current.derivedDataDirectory().isAncestor(of: absolutePath) {
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
            let type: XCActivityIssueType =
                switch notice.type {
                case .analyzerWarning, .clangWarning, .deprecatedWarning, .interfaceBuilderWarning,
                     .swiftWarning, .projectWarning, .note:
                    .warning
                case .error, .clangError, .swiftError, .linkerError, .scriptPhaseError,
                     .failedCommandError, .packageLoadingError:
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
