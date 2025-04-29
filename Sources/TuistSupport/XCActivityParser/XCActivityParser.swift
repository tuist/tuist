import Foundation
import Mockable
import Path
import XCLogParser
import Path
import FileSystem

@Mockable
public protocol XCActivityParsing {
    func mostRecentActivityLogPath(projectDerivedDataDirectory: AbsolutePath, after: Date) async throws -> AbsolutePath?
    func parse(_ path: AbsolutePath) throws -> XCActivityLog
}

public struct XCActivityParser: XCActivityParsing {
    let fileSystem: FileSystem
    let environment: Environmenting
    
    public init(fileSystem: FileSystem = FileSystem(), environment: Environmenting = Environment.shared) {
        self.fileSystem = fileSystem
        self.environment = environment
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
