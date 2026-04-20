import FileSystem
import Foundation
import Mockable
import Path
import TuistCASAnalytics
import TuistEnvironment
import TuistGit
import TuistLogging
import TuistRootDirectoryLocator
import TuistSupport
import XCActivityLogParser
import XCLogParser

enum XCActivityLogControllerError: LocalizedError, Equatable {
    case failedToParseActivityLog(path: AbsolutePath, reason: String)

    var errorDescription: String? {
        switch self {
        case let .failedToParseActivityLog(path, reason):
            return "Failed to parse the activity log at \(path.pathString): \(reason)"
        }
    }

    static func wrap(_ error: Error, path: AbsolutePath) -> XCActivityLogControllerError {
        .failedToParseActivityLog(path: path, reason: error.localizedDescription)
    }
}

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
        let logStoreManifest: XCLogStoreManifestPlist
        do {
            logStoreManifest = try await fileSystem.readPlistFile(
                at: logStoreManifestPlistPath
            )
        } catch {
            throw XCActivityLogControllerError.wrap(error, path: logStoreManifestPlistPath)
        }

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
            let activityLog: IDEActivityLog
            do {
                activityLog = try XCLogParser.ActivityParser().parseActivityLogInURL(
                    activityLogPath.url,
                    redacted: false,
                    withoutBuildSpecificInformation: false
                )
            } catch {
                throw XCActivityLogControllerError.wrap(error, path: activityLogPath)
            }
            let buildStep: BuildStep
            do {
                buildStep = try XCLogParser.ParserBuildSteps(
                    omitWarningsDetails: true,
                    omitNotesDetails: true,
                    truncLargeIssues: true
                )
                .parse(activityLog: activityLog)
            } catch {
                throw XCActivityLogControllerError.wrap(error, path: activityLogPath)
            }

            for (targetName, targetBuildDuration) in flattenedXCLogParserBuildStep([buildStep])
                .filter({ $0.title.starts(with: "Build target") }).map({
                    ($0.signature, $0.subSteps.reduce(into: 0) { duration, subStep in
                        duration += subStep.compilationDuration * 1000 // From seconds to milliseconds
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
        guard try await fileSystem.exists(logManifestPlistPath) else {
            Logger.current.debug("Activity log manifest not found at \(logManifestPlistPath.pathString)")
            return nil
        }
        Logger.current.debug("Activity log manifest found at \(logManifestPlistPath.pathString)")
        let plist: XCLogStoreManifestPlist
        do {
            plist = try await fileSystem.readPlistFile(
                at: logManifestPlistPath
            )
        } catch {
            throw XCActivityLogControllerError.wrap(error, path: logManifestPlistPath)
        }
        Logger.current.debug("Activity log manifest contains \(plist.logs.count) log(s)")

        let logFiles = plist.logs.values.map {
            XCActivityLogFile(
                path: logsBuildDirectoryPath.appending(component: $0.fileName),
                timeStoppedRecording: Date(timeIntervalSinceReferenceDate: $0.timeStoppedRecording),
                signature: $0.signature
            )
        }
        let sortedLogFiles = logFiles.sorted(by: {
            $0.timeStoppedRecording > $1.timeStoppedRecording
        })
        for logFile in sortedLogFiles.prefix(5) {
            Logger.current
                .debug(
                    "Activity log entry: signature=\(logFile.signature), timeStoppedRecording=\(logFile.timeStoppedRecording) (timeIntervalSinceReferenceDate: \(logFile.timeStoppedRecording.timeIntervalSinceReferenceDate)), path=\(logFile.path.pathString)"
                )
        }
        let logFile = sortedLogFiles
            .filter(filter)
            .first
        if logFile == nil {
            Logger.current.debug("No activity log matched the filter (all \(sortedLogFiles.count) entries were filtered out)")
        }
        return logFile
    }

    /// Parses an xcactivitylog file into an `XCActivityLog` model.
    /// This is temporary and will be fully removed once all build processing happens server-side.
    public func parse(_ path: AbsolutePath) async throws -> XCActivityLog {
        let stateDirectory = Environment.current.stateDirectory
        let rootDirectory = try await rootDirectory()

        let parsed: BuildData
        do {
            parsed = try await XCActivityLogParser().parse(
                xcactivitylogURL: path.url,
                casAnalyticsDatabasePath: stateDirectory.appending(component: CASAnalyticsDatabase.databaseName),
                legacyCASMetadataPath: stateDirectory
            )
        } catch {
            throw XCActivityLogControllerError.wrap(error, path: path)
        }

        return XCActivityLog(
            version: parsed.version,
            mainSection: XCActivityLogSection(
                uniqueIdentifier: parsed.unique_identifier,
                timeStartedRecording: parsed.time_started_recording,
                timeStoppedRecording: parsed.time_stopped_recording
            ),
            buildStep: XCActivityBuildStep(
                errorCount: parsed.error_count
            ),
            category: parsed.category == "clean" ? .clean : .incremental,
            issues: parsed.issues.map { issue in
                XCActivityIssue(
                    type: issue.type == "warning" ? .warning : .error,
                    target: issue.target,
                    project: issue.project,
                    title: issue.title,
                    signature: issue.signature,
                    stepType: XCActivityStepType(stepTypeString: issue.step_type),
                    path: issue.path.flatMap { relativePath($0, rootDirectory: rootDirectory) },
                    message: issue.message,
                    startingLine: issue.starting_line,
                    endingLine: issue.ending_line,
                    startingColumn: issue.starting_column,
                    endingColumn: issue.ending_column
                )
            },
            files: parsed.files.compactMap { file in
                let fileType: XCActivityBuildFileType = file.type == "swift" ? .swift : .c
                guard let path = relativePath(file.path, rootDirectory: rootDirectory) else { return nil }
                return XCActivityBuildFile(
                    type: fileType,
                    target: file.target,
                    project: file.project,
                    path: path,
                    compilationDuration: file.compilation_duration
                )
            },
            targets: parsed.targets.map { target in
                XCActivityTarget(
                    name: target.name,
                    project: target.project,
                    buildDuration: target.build_duration,
                    compilationDuration: target.compilation_duration,
                    status: target.status == "failure" ? .failure : .success
                )
            },
            cacheableTasks: parsed.cacheable_tasks.map { task in
                CacheableTask(
                    key: task.key,
                    status: task.status == "miss" ? .miss : (task.status == "hit_remote" ? .remoteHit : .localHit),
                    type: task.type == "swift" ? .swift : .clang,
                    readDuration: task.read_duration,
                    writeDuration: task.write_duration,
                    description: task.description,
                    nodeIDs: task.cas_output_node_ids
                )
            },
            casOutputs: parsed.cas_outputs.compactMap { output in
                guard let type = output.type.flatMap({ CASOutputType(rawValue: $0) }) else { return nil }
                return CASOutput(
                    nodeID: output.node_id,
                    checksum: output.checksum,
                    size: output.size,
                    duration: output.duration,
                    compressedSize: output.compressed_size,
                    operation: output.operation == "download" ? .download : .upload,
                    type: type
                )
            }
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

    private func relativePath(_ absolutePathString: String, rootDirectory: AbsolutePath?) -> RelativePath? {
        guard let file = try? AbsolutePath(validating: absolutePathString) else { return nil }
        return file.relative(to: rootDirectory ?? AbsolutePath.root)
    }
}
