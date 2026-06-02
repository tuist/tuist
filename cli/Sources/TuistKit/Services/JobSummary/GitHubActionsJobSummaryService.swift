import FileSystem
import Foundation
import Mockable
import Path
import TuistCI
import TuistEnvironment
import TuistLogging
import TuistServer

@Mockable
public protocol GitHubActionsJobSummaryServicing {
    /// Fetches the server-rendered "Tuist Run Report" for the given git ref and writes it to the
    /// GitHub Actions job summary (`$GITHUB_STEP_SUMMARY`). It's a no-op unless the command produced
    /// a report, is running in GitHub Actions, and the summary file is available. It never throws so
    /// it can't fail the command it's reporting on.
    func writeJobSummary(
        gitRef: String?,
        hasReport: Bool,
        fullHandle: String,
        serverURL: URL
    ) async
}

public struct GitHubActionsJobSummaryService: GitHubActionsJobSummaryServicing {
    private let fileSystem: FileSysteming
    private let ciController: CIControlling
    private let getRunJobSummaryService: GetRunJobSummaryServicing
    private let maxAttempts: Int
    private let retryDelay: TimeInterval

    public init(
        fileSystem: FileSysteming = FileSystem(),
        ciController: CIControlling = CIController(),
        getRunJobSummaryService: GetRunJobSummaryServicing = GetRunJobSummaryService(),
        maxAttempts: Int = 6,
        retryDelay: TimeInterval = 3
    ) {
        self.fileSystem = fileSystem
        self.ciController = ciController
        self.getRunJobSummaryService = getRunJobSummaryService
        self.maxAttempts = maxAttempts
        self.retryDelay = retryDelay
    }

    public func writeJobSummary(
        gitRef: String?,
        hasReport: Bool,
        fullHandle: String,
        serverURL: URL
    ) async {
        guard hasReport, let gitRef else { return }
        guard ciController.ciInfo()?.provider == .github else { return }
        let summaryPath = Environment.current.variables["GITHUB_STEP_SUMMARY"]
        guard let summaryPath, !summaryPath.isEmpty else { return }

        do {
            guard let markdown = try await fetchWithRetry(fullHandle: fullHandle, gitRef: gitRef, serverURL: serverURL),
                  !markdown.isEmpty
            else { return }
            try await append(markdown: markdown, toFileAt: summaryPath)
            Logger.current.debug("Wrote the Tuist Run Report to the GitHub Actions job summary.")
        } catch {
            Logger.current.debug("Failed to write the GitHub Actions job summary: \(String(describing: error))")
        }
    }

    private func fetchWithRetry(fullHandle: String, gitRef: String, serverURL: URL) async throws -> String? {
        for attempt in 0 ..< maxAttempts {
            let markdown = try await getRunJobSummaryService.getRunJobSummary(
                fullHandle: fullHandle,
                gitRef: gitRef,
                serverURL: serverURL
            )
            if let markdown, !markdown.isEmpty {
                return markdown
            }
            if attempt < maxAttempts - 1 {
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }
        return nil
    }

    private func append(markdown: String, toFileAt summaryPath: String) async throws {
        let outputPath = try AbsolutePath(validating: summaryPath)
        let existing = (try? await fileSystem.readTextFile(at: outputPath)) ?? ""
        try await fileSystem.writeText(
            existing + markdown + "\n",
            at: outputPath,
            encoding: .utf8,
            options: [.overwrite]
        )
    }
}
