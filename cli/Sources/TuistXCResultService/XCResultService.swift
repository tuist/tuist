import FileSystem
import Foundation
import Mockable
import Path
import TuistLogging
import TuistSupport
import XCResultParser

@Mockable
public protocol XCResultServicing {
    func parse(path: AbsolutePath, rootDirectory: AbsolutePath?) async throws -> TestSummary?
    func mostRecentXCResultFile(projectDerivedDataDirectory: AbsolutePath) async throws -> AbsolutePath?
}

public struct XCResultService: XCResultServicing {
    private let fileSystem: FileSysteming
    private let parser: XCResultParser

    public init(
        fileSystem: FileSysteming = FileSystem(),
        parser: XCResultParser = XCResultParser()
    ) {
        self.fileSystem = fileSystem
        self.parser = parser
    }

    public func mostRecentXCResultFile(projectDerivedDataDirectory: AbsolutePath)
        async throws -> AbsolutePath?
    {
        let logsBuildDirectoryPath = projectDerivedDataDirectory.appending(
            components: "Logs", "Test"
        )
        let logManifestPlistPath = logsBuildDirectoryPath.appending(
            components: "LogStoreManifest.plist"
        )
        guard try await fileSystem.exists(logManifestPlistPath) else {
            Logger.current.debug("Test log manifest not found at \(logManifestPlistPath.pathString)")
            return nil
        }
        Logger.current.debug("Test log manifest found at \(logManifestPlistPath.pathString)")
        let plist: XCLogStoreManifestPlist = try await fileSystem.readPlistFile(
            at: logManifestPlistPath
        )
        Logger.current.debug("Test log manifest contains \(plist.logs.count) log(s)")

        guard let latestLog = plist.logs.values.sorted(by: {
            $0.timeStoppedRecording > $1.timeStoppedRecording
        }).first
        else {
            Logger.current.debug("Test log manifest has no log entries")
            return nil
        }

        let resultPath = logsBuildDirectoryPath.appending(component: latestLog.fileName)
        Logger.current
            .debug("Most recent test log: \(latestLog.fileName), timeStoppedRecording=\(latestLog.timeStoppedRecording)")
        return resultPath
    }

    public func parse(path: AbsolutePath, rootDirectory: AbsolutePath?) async throws -> TestSummary? {
        try await parser.parse(path: path, rootDirectory: rootDirectory)
    }
}
