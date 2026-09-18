import Foundation
import Mockable
import Noora
import Path
import TuistAlert
import TuistConfigLoader
import TuistEnvironment
import TuistGit
import TuistLoader
import TuistServer
import TuistSupport

@Mockable
protocol CoverageCompleteCommandServicing {
    func run(path: String?, fullHandle: String?, commit: String?, json: Bool) async throws
}

enum CoverageCompleteCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle
    case missingCommit

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't signal the coverage completion because the project's full handle is missing. Pass --full-handle or run it from a Tuist project."
        case .missingCommit:
            return "We couldn't tell which commit's coverage pipeline finished. Pass --commit, or run it from a Git checkout."
        }
    }
}

struct CoverageCompleteCommandService: CoverageCompleteCommandServicing {
    private let completeCommitCoverageService: CompleteCommitCoverageServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading
    private let gitController: GitControlling

    init(
        completeCommitCoverageService: CompleteCommitCoverageServicing = CompleteCommitCoverageService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader(),
        gitController: GitControlling = GitController()
    ) {
        self.completeCommitCoverageService = completeCommitCoverageService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
        self.gitController = gitController
    }

    func run(path: String?, fullHandle: String?, commit: String?, json: Bool) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: directoryPath)

        guard let fullHandle = fullHandle ?? config.fullHandle else {
            throw CoverageCompleteCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        var sha = commit
        if sha == nil {
            sha = try? await gitController.gitInfo(workingDirectory: directoryPath).sha
        }
        guard let sha, !sha.isEmpty else {
            throw CoverageCompleteCommandServiceError.missingCommit
        }

        let coverage = try await completeCommitCoverageService.completeCommitCoverage(
            fullHandle: fullHandle,
            serverURL: serverURL,
            gitCommitSHA: sha
        )

        if json {
            try Noora.current.json(
                CoverageCompleteOutput(
                    git_commit_sha: coverage.gitCommitSHA,
                    coverage: coverage.coverage,
                    covered_lines: coverage.coveredLines,
                    executable_lines: coverage.executableLines,
                    schemes: coverage.schemes,
                    partial_schemes: coverage.partialSchemes,
                    complete: coverage.complete
                )
            )
            return
        }

        let schemes = coverage.schemes.isEmpty ? "no scheme" : coverage.schemes.joined(separator: ", ")
        let partial = coverage.partialSchemes.isEmpty ? "" : " (partial: \(coverage.partialSchemes.joined(separator: ", ")))"

        AlertController.current.success(
            .alert(
                "Coverage of commit \(coverage.gitCommitSHA.prefix(7)) is complete: \(coverage.coverage)% over \(schemes)\(partial)."
            )
        )
    }
}

private struct CoverageCompleteOutput: Codable {
    let git_commit_sha: String
    let coverage: Double
    let covered_lines: Int
    let executable_lines: Int
    let schemes: [String]
    let partial_schemes: [String]
    let complete: Bool
}
