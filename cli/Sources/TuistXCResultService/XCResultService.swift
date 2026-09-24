import FileSystem
import Foundation
import Mockable
import Path
import TuistAlert
import TuistLogging
import TuistSupport
import XCResultParser

@Mockable
public protocol XCResultServicing {
    func parse(path: AbsolutePath, rootDirectory: AbsolutePath?) async throws -> TestSummary?
    func parseTestStatuses(path: AbsolutePath) async throws -> TestResultStatuses
    func coveredFilePaths(path: AbsolutePath) async throws -> [String]?
    func parseCoverage(path: AbsolutePath, manifest: XcodeCoverageManifest) async throws -> XcodeCoverageReport?
    /// The same, streamed to `output` as one JSON object per source file, for bundles too large
    /// to hold in memory.
    func parseCoverage(
        path: AbsolutePath,
        manifest: XcodeCoverageManifest,
        into output: AbsolutePath
    ) async throws -> XcodeCoverageSummary?
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
        try await parser.parse(path: path, rootDirectory: rootDirectory)
    }

    public func coveredFilePaths(path: AbsolutePath) async throws -> [String]? {
        try await coverageParser.coveredFilePaths(resultBundlePath: path)
    }

    public func parseCoverage(path: AbsolutePath, manifest: XcodeCoverageManifest) async throws -> XcodeCoverageReport? {
        do {
            return try await coverageParser.parse(resultBundlePath: path, manifest: manifest)
        } catch {
            // Coverage only enriches the run: a report xccov cannot read must not cost the test results.
            AlertController.current.warning(
                .alert("Failed to read the code coverage from \(path.pathString): \(error.localizedDescription)")
            )
            return nil
        }
    }

    public func parseCoverage(
        path: AbsolutePath,
        manifest: XcodeCoverageManifest,
        into output: AbsolutePath
    ) async throws -> XcodeCoverageSummary? {
        do {
            return try await coverageParser.parse(resultBundlePath: path, manifest: manifest, into: output)
        } catch {
            AlertController.current.warning(
                .alert("Failed to read the code coverage from \(path.pathString): \(error.localizedDescription)")
            )
            return nil
        }
    }

    public func parseTestStatuses(path: AbsolutePath) async throws -> TestResultStatuses {
        try await parser.parseTestStatuses(path: path)
    }
}
