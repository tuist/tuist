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

        return XCActivityLog(
            version: activityLog.version,
            mainSection: XCActivityLogSection(
                uniqueIdentifier: activityLog.mainSection.uniqueIdentifier,
                timeStartedRecording: activityLog.mainSection.timeStartedRecording,
                timeStoppedRecording: activityLog.mainSection.timeStoppedRecording
            ),
            buildStep: XCActivityBuildStep(
                errorCount: buildStep.errorCount
            )
        )
    }
}
