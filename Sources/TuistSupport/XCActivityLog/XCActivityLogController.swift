import FileSystem
import Foundation
import Mockable
import Path
import XCLogParser

@Mockable
public protocol XCActivityLogControlling {
    func mostRecentActivityLogPath(projectDerivedDataDirectory: AbsolutePath, after: Date) async throws -> AbsolutePath?
    func buildTimesByTarget(projectDerivedDataDirectory: AbsolutePath) async throws -> [String: Double]
    func parse(_ path: AbsolutePath) throws -> XCActivityLog
}

public struct XCActivityLogController: XCActivityLogControlling {
    let fileSystem: FileSystem
    let environment: Environmenting

    public init(fileSystem: FileSystem = FileSystem(), environment: Environmenting = Environment.current) {
        self.fileSystem = fileSystem
        self.environment = environment
    }

    public func buildTimesByTarget(projectDerivedDataDirectory: AbsolutePath) async throws -> [String: Double] {
        let buildLogsPath = projectDerivedDataDirectory.appending(components: [
            "Logs",
            "Build",
        ])
        let logStoreManifestPlistPath = buildLogsPath.appending(components: ["LogStoreManifest.plist"])
        let logStoreManifest: XCLogStoreManifestPlist = try await fileSystem.readPlistFile(at: logStoreManifestPlistPath)

        let activityLogPaths = logStoreManifest.logs.keys.map { buildLogsPath.appending(components: ["\($0).xcactivitylog"]) }

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
                .filter({ $0.title.starts(with: "Build target") }).map({ ($0.signature, $0.duration) })
            {
                /**
                 If a target supports multiple platforms, the time will persist is the time of the latest platform that we built.
                 */
                buildTimes[targetName] = targetBuildDuration
            }
        }

        return buildTimes
    }

    private func flattenedXCLogParserBuildStep(_ buildSteps: [XCLogParser.BuildStep]) -> [XCLogParser.BuildStep] {
        buildSteps.flatMap { step in
            var flattened = [step]
            if !step.subSteps.isEmpty {
                flattened.append(contentsOf: flattenedXCLogParserBuildStep(step.subSteps))
            }
            return flattened
        }
    }

    public func mostRecentActivityLogPath(projectDerivedDataDirectory: AbsolutePath, after: Date) async throws -> AbsolutePath? {
        let logsBuildDirectoryPath = projectDerivedDataDirectory.appending(components: "Logs", "Build")
        let logManifestPlistPath = logsBuildDirectoryPath.appending(components: "LogStoreManifest.plist")
        guard try await fileSystem.exists(logManifestPlistPath) else { return nil }
        let plist: XCLogStoreManifestPlist = try await fileSystem.readPlistFile(at: logManifestPlistPath)

        guard let latestLog = plist.logs.values.sorted(by: { $0.timeStoppedRecording > $1.timeStoppedRecording }).first,
              environment
              .workspacePath == nil ||
              (after.timeIntervalSinceReferenceDate - 10 ..< after.timeIntervalSinceReferenceDate + 10) ~=
              latestLog.timeStoppedRecording
        else {
            return nil
        }
        return logsBuildDirectoryPath.appending(component: latestLog.fileName)
    }

    public func parse(_ path: AbsolutePath) throws -> XCActivityLog {
        let activityLog = try XCLogParser.ActivityParser().parseActivityLogInURL(
            path.url,
            redacted: false,
            withoutBuildSpecificInformation: false
        )

        let buildStep = try XCLogParser.ParserBuildSteps(
            omitWarningsDetails: true,
            omitNotesDetails: true,
            truncLargeIssues: true
        )
        .parse(activityLog: activityLog)

        let steps = flattenedXCLogParserBuildStep([buildStep])
        let targets = steps.filter { $0.type == .target }
            .filter { $0.title.contains("Build target ") }
            .map {
                XCActivityTarget(
                    name: $0.title.replacingOccurrences(of: "Build target ", with: ""),
                    step: $0
                )
            }

        let category = buildCategory(
            steps: steps.filter { $0.type == .detail && $0.detailStepType != .swiftAggregatedCompilation },
            targets: targets
        )

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
            category: category
        )
    }

    private func buildCategory(steps: [BuildStep], targets: [XCActivityTarget]) -> XCActivityBuildCategory {
        let targetIdentifiers = targetIdentifiers(buildSteps: steps)
        var targetsCompiledCount = [String: Int]()

        for target in targets {
            targetsCompiledCount[target.step.identifier] = 0
        }

        let buildSteps = steps
            .filter { $0.detailStepType != .other && $0.detailStepType != .scriptExecution && $0.detailStepType != .copySwiftLibs
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
            let targetFilesCount = buildSteps.filter { targetIdentifiers[$0.identifier]! == target }.count
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
            return dictionary.merging(zip([target.identifier], [target.identifier])) { _, new in new }
        }

        let steps = buildSteps.filter { $0.type == .detail && $0.detailStepType != .swiftAggregatedCompilation }

        for step in steps.filter({ $0.detailStepType != .swiftCompilation }) {
            targetIdentifiers[step.identifier] = step.parentIdentifier
        }

        let swiftAggregatedSteps = buildSteps.filter { $0.type == .detail
            && $0.detailStepType == .swiftAggregatedCompilation
        }

        let swiftAggregatedStepsIds = swiftAggregatedSteps.reduce([String: String]()) {
            dictionary, step -> [String: String] in
            return dictionary.merging(zip([step.identifier], [step.parentIdentifier])) { _, new in new }
        }

        for step in steps
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
}

private struct XCActivityTarget {
    let name: String
    let step: BuildStep
}
