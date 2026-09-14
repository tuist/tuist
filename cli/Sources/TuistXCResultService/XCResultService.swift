import FileSystem
import Foundation
import Mockable
import Path
import TuistLogging
import TuistSupport
import XCResultParser

@Mockable
public protocol XCResultServicing {
    /// Parses the bundle's tests and, when the run gathered code coverage, the coverage report.
    func parse(path: AbsolutePath, rootDirectory: AbsolutePath?) async throws -> TestSummary?
    func parseTestStatuses(path: AbsolutePath) async throws -> TestResultStatuses
    /// The bundle's coverage report on its own, or nil when the run gathered none.
    func parseCoverage(path: AbsolutePath, rootDirectory: AbsolutePath?) async throws -> XcodeCoverageReport?
    func mostRecentXCResultFile(projectDerivedDataDirectory: AbsolutePath) async throws -> AbsolutePath?
}

public struct XCResultService: XCResultServicing {
    private let fileSystem: FileSysteming
    private let parser: XCResultParser
    private let coverageParser: XcodeCoverageParsing

    public init(
        fileSystem: FileSysteming = FileSystem(),
        parser: XCResultParser = XCResultParser(),
        coverageParser: XcodeCoverageParsing = XcodeCoverageParser()
    ) {
        self.fileSystem = fileSystem
        self.parser = parser
        self.coverageParser = coverageParser
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
        guard var summary = try await parser.parse(path: path, rootDirectory: rootDirectory) else { return nil }
        summary.coverage = try await parseCoverage(path: path, rootDirectory: rootDirectory)
        return summary
    }

    public func parseCoverage(path: AbsolutePath, rootDirectory: AbsolutePath?) async throws -> XcodeCoverageReport? {
        do {
            return try await coverageParser.parse(resultBundlePath: path, rootDirectory: rootDirectory)
        } catch {
            // Coverage only enriches the run: a report xccov cannot read must not cost the test results.
            Logger.current.warning("Failed to read the code coverage from \(path.pathString): \(error.localizedDescription)")
            return nil
        }
    }

    public func parseTestStatuses(path: AbsolutePath) async throws -> TestResultStatuses {
        try await parser.parseTestStatuses(path: path)
    }
}
