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
    case earlyAccess

    var errorDescription: String? {
        switch self {
        case .earlyAccess:
            return "Code coverage is in early access. Set TUIST_FEATURE_FLAG_COVERAGE=1 to use it; your account needs it enabled too."
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
        guard ClientFeatureFlags.contains("COVERAGE") else { throw CoverageCompleteCommandServiceError.earlyAccess }
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
                    gitCommitSHA: coverage.gitCommitSHA,
                    coverage: coverage.coverage,
                    coveredLines: coverage.coveredLines,
                    executableLines: coverage.executableLines,
                    schemes: coverage.schemes,
                    partialSchemes: coverage.partialSchemes,
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
    let gitCommitSHA: String
    let coverage: Double
    let coveredLines: Int
    let executableLines: Int
    let schemes: [String]
    let partialSchemes: [String]
    let complete: Bool

    enum CodingKeys: String, CodingKey {
        case gitCommitSHA = "git_commit_sha"
        case coverage
        case coveredLines = "covered_lines"
        case executableLines = "executable_lines"
        case schemes
        case partialSchemes = "partial_schemes"
        case complete
    }
}
