import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer
import TuistSupport

enum CoverageReadCommandServiceError: Equatable, LocalizedError {
    case earlyAccess
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .earlyAccess:
            return "Code coverage is in early access. Set TUIST_FEATURE_FLAG_COVERAGE=1 to use it; your account needs it enabled too."
        case .missingFullHandle:
            return "The project's full handle is missing. Pass --full-handle or run the command from a Tuist project."
        }
    }
}

struct CoverageReadContext {
    let fullHandle: String
    let serverURL: URL

    static func resolve(
        path: String?,
        fullHandle: String?,
        configLoader: ConfigLoading,
        serverEnvironmentService: ServerEnvironmentServicing
    ) async throws -> CoverageReadContext {
        guard ClientFeatureFlags.contains("COVERAGE") else { throw CoverageReadCommandServiceError.earlyAccess }
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let fullHandle = fullHandle ?? config.fullHandle else {
            throw CoverageReadCommandServiceError.missingFullHandle
        }
        return CoverageReadContext(
            fullHandle: fullHandle,
            serverURL: try serverEnvironmentService.url(configServerURL: config.url)
        )
    }

    /// The commit to read: the given one, otherwise the branch's latest complete commit.
    func commitSHA(commit: String?, branch: String?, coverageService: CoverageServicing) async throws -> String {
        if let commit, !commit.isEmpty { return commit }
        return try await coverageService.getBranchCoverage(fullHandle: fullHandle, serverURL: serverURL, branch: branch)
            .git_commit_sha
    }

    static func percentage(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }
}

struct CoverageShowCommandService {
    private let coverageService: CoverageServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        coverageService: CoverageServicing = CoverageService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.coverageService = coverageService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(path: String?, fullHandle: String?, branch: String?, commit: String?, json: Bool) async throws {
        let context = try await CoverageReadContext.resolve(
            path: path,
            fullHandle: fullHandle,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService
        )

        if let commit, !commit.isEmpty {
            let coverage = try await coverageService.getCommitCoverage(
                fullHandle: context.fullHandle,
                serverURL: context.serverURL,
                commitSHA: commit
            )
            if json { return try Noora.current.json(coverage) }
            return render(Self.summary(of: coverage))
        }

        let coverage = try await coverageService.getBranchCoverage(
            fullHandle: context.fullHandle,
            serverURL: context.serverURL,
            branch: branch
        )
        if json { return try Noora.current.json(coverage) }
        render(Self.summary(of: coverage))
    }

    private static func summary(of coverage: Operations.getCommitCoverage.Output.Ok.Body.jsonPayload) -> Summary {
        Summary(
            branch: nil,
            gitCommitSHA: coverage.git_commit_sha,
            coverage: coverage.coverage,
            coveredLines: coverage.covered_lines,
            executableLines: coverage.executable_lines,
            measuredFilesCount: coverage.measured_files_count,
            complete: coverage.complete,
            schemes: coverage.schemes,
            targets: coverage.targets.map {
                Target(name: $0.name, coverage: $0.coverage, coveredLines: $0.covered_lines, executableLines: $0.executable_lines)
            }
        )
    }

    private static func summary(of coverage: Operations.getBranchCoverage.Output.Ok.Body.jsonPayload) -> Summary {
        Summary(
            branch: coverage.branch,
            gitCommitSHA: coverage.git_commit_sha,
            coverage: coverage.coverage,
            coveredLines: coverage.covered_lines,
            executableLines: coverage.executable_lines,
            measuredFilesCount: coverage.measured_files_count,
            complete: coverage.complete,
            schemes: coverage.schemes,
            targets: coverage.targets.map {
                Target(name: $0.name, coverage: $0.coverage, coveredLines: $0.covered_lines, executableLines: $0.executable_lines)
            }
        )
    }

    private struct Target {
        let name: String
        let coverage: Double
        let coveredLines: Int
        let executableLines: Int
    }

    private struct Summary {
        let branch: String?
        let gitCommitSHA: String
        let coverage: Double
        let coveredLines: Int
        let executableLines: Int
        let measuredFilesCount: Int
        let complete: Bool
        let schemes: [String]
        let targets: [Target]
    }

    private func render(_ summary: Summary) {
        let targets = summary.targets
        var info = ["Coverage".bold()] + (summary.branch.map { ["Branch: \($0)"] } ?? []) + [
            "Commit: \(summary.gitCommitSHA)",
            "Coverage: \(CoverageReadContext.percentage(summary.coverage)) (\(summary.coveredLines) of \(summary.executableLines) lines)",
            "Measured Files: \(summary.measuredFilesCount)",
            "Complete: \(summary.complete ? "Yes" : "No")",
        ]
        let schemes = summary.schemes.filter { !$0.isEmpty }
        if !schemes.isEmpty { info.append("Schemes: \(schemes.joined(separator: ", "))") }

        if !targets.isEmpty {
            info.append("")
            info.append("Targets".bold())
            for target in targets {
                info.append(
                    "\(target.name): \(CoverageReadContext.percentage(target.coverage)) (\(target.coveredLines) of \(target.executableLines) lines)"
                )
            }
        }
        Noora.current.passthrough("\(info.joined(separator: "\n"))")
    }
}

struct CoverageFilesCommandService {
    private let coverageService: CoverageServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        coverageService: CoverageServicing = CoverageService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.coverageService = coverageService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        path: String?,
        fullHandle: String?,
        branch: String?,
        commit: String?,
        search: String?,
        sortBy: String?,
        sortOrder: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        let context = try await CoverageReadContext.resolve(
            path: path,
            fullHandle: fullHandle,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService
        )
        let sha = try await context.commitSHA(commit: commit, branch: branch, coverageService: coverageService)
        let startPage = (page ?? 1) - 1
        let pageSize = pageSize ?? 20

        let fetch = { (pageIndex: Int) in
            try await coverageService.listCoverageFiles(
                fullHandle: context.fullHandle,
                serverURL: context.serverURL,
                commitSHA: sha,
                search: search,
                sortBy: sortBy,
                sortOrder: sortOrder,
                page: pageIndex + 1,
                pageSize: pageSize
            )
        }

        let initialPage = try await fetch(startPage)

        if json {
            try Noora.current.json(initialPage)
            return
        }

        if initialPage.files.isEmpty {
            Noora.current.passthrough("No file coverage found for commit \(sha).")
            return
        }

        try await Noora.current.paginatedTable(
            headers: ["Path", "Coverage", "Covered Lines", "Executable Lines"],
            pageSize: pageSize,
            totalPages: initialPage.pagination_metadata.total_pages ?? 1,
            startPage: startPage,
            loadPage: { pageIndex in
                let page = pageIndex == startPage ? initialPage : try await fetch(pageIndex)
                return page.files.map { file in
                    [
                        file.path,
                        CoverageReadContext.percentage(file.coverage),
                        "\(file.covered_lines)",
                        "\(file.executable_lines)",
                    ]
                }
            }
        )
    }
}

struct CoverageFileCommandService {
    private let coverageService: CoverageServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        coverageService: CoverageServicing = CoverageService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.coverageService = coverageService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        path: String?,
        fullHandle: String?,
        branch: String?,
        commit: String?,
        filePath: String,
        includeLines: Bool,
        json: Bool
    ) async throws {
        let context = try await CoverageReadContext.resolve(
            path: path,
            fullHandle: fullHandle,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService
        )
        let sha = try await context.commitSHA(commit: commit, branch: branch, coverageService: coverageService)
        let file = try await coverageService.getCoverageFile(
            fullHandle: context.fullHandle,
            serverURL: context.serverURL,
            commitSHA: sha,
            path: filePath,
            includeLines: includeLines
        )

        if json {
            try Noora.current.json(file)
            return
        }

        var info = [
            file.path.bold(),
            "Commit: \(file.git_commit_sha)",
            "Coverage: \(CoverageReadContext.percentage(file.coverage)) (\(file.covered_lines) of \(file.executable_lines) lines)",
        ]
        if !file.targets.isEmpty { info.append("Targets: \(file.targets.joined(separator: ", "))") }

        if let lines = file.lines {
            let uncovered = lines.filter { $0.count == 0 }.map(\.line)
            info.append("Uncovered Lines: \(uncovered.isEmpty ? "none" : Self.ranges(uncovered))")
        }

        if !file.functions.isEmpty {
            info.append("")
            info.append("Functions".bold())
            for function in file.functions {
                let times = function.execution_count == 1 ? "1 time" : "\(function.execution_count) times"
                info.append("\(function.name) (line \(function.line_number)): called \(times)")
            }
        }
        Noora.current.passthrough("\(info.joined(separator: "\n"))")
    }

    /// Collapses sorted line numbers into ranges, such as `3-5, 9`.
    static func ranges(_ lines: [Int]) -> String {
        var ranges: [String] = []
        var start: Int?
        var previous: Int?
        for line in lines.sorted() {
            if let current = previous, line == current + 1 {
                previous = line
                continue
            }
            if let start, let previous { ranges.append(start == previous ? "\(start)" : "\(start)-\(previous)") }
            start = line
            previous = line
        }
        if let start, let previous { ranges.append(start == previous ? "\(start)" : "\(start)-\(previous)") }
        return ranges.joined(separator: ", ")
    }
}
