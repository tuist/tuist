import Foundation
import Mockable
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistServer

@Mockable
protocol BuildShowCommandServicing {
    func run(
        fullHandle: String?,
        buildId: String,
        path: String?,
        json: Bool
    ) async throws
}

enum BuildShowCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't show the build because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

final class BuildShowCommandService: BuildShowCommandServicing {
    private let getBuildService: GetBuildServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        getBuildService: GetBuildServicing = GetBuildService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.getBuildService = getBuildService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String?,
        buildId: String,
        path: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = fullHandle ?? config.fullHandle else {
            throw BuildShowCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let build = try await getBuildService.getBuild(
            fullHandle: resolvedFullHandle,
            buildId: buildId,
            serverURL: serverURL
        )

        if json {
            try Noora.current.json(build)
            return
        }

        let buildInfo = formatBuildInfo(build)
        Noora.current.passthrough("\(buildInfo)")
    }

    func formatBuildInfo(_ build: Build) -> String {
        var info = [
            "Build".bold(),
            "ID: \(build.id)",
            "Status: \(build.status.rawValue)",
            "Duration: \(formatDuration(build.duration))",
            "CI: \(build.is_ci ? "Yes" : "No")",
        ]

        if let scheme = build.scheme {
            info.append("Scheme: \(scheme)")
        }

        if let configuration = build.configuration {
            info.append("Configuration: \(configuration)")
        }

        if let category = build.category {
            info.append("Category: \(category.rawValue)")
        }

        if let xcodeVersion = build.xcode_version {
            info.append("Xcode Version: \(xcodeVersion)")
        }

        if let macosVersion = build.macos_version {
            info.append("macOS Version: \(macosVersion)")
        }

        if let modelIdentifier = build.model_identifier {
            info.append("Machine: \(modelIdentifier)")
        }

        if let gitBranch = build.git_branch {
            info.append("Git Branch: \(gitBranch)")
        }

        if let gitCommitSha = build.git_commit_sha {
            info.append("Git Commit: \(gitCommitSha)")
        }

        if let gitRef = build.git_ref {
            info.append("Git Ref: \(gitRef)")
        }

        info.append("")
        info.append("Cache Statistics".bold())
        info.append("Total Cacheable Tasks: \(build.cacheable_tasks_count)")
        info.append("Local Cache Hits: \(build.cacheable_task_local_hits_count)")
        info.append("Remote Cache Hits: \(build.cacheable_task_remote_hits_count)")

        let misses = build.cacheable_tasks_count - build.cacheable_task_local_hits_count - build
            .cacheable_task_remote_hits_count
        info.append("Cache Misses: \(misses)")

        if build.cacheable_tasks_count > 0 {
            let hitRate =
                Double(build.cacheable_task_local_hits_count + build.cacheable_task_remote_hits_count)
                    / Double(build.cacheable_tasks_count) * 100
            info.append("Hit Rate: \(String(format: "%.1f", hitRate))%")
        }

        info.append("")
        info.append("Created: \(formatDate(build.inserted_at))")

        return info.joined(separator: "\n")
    }

    private func formatDuration(_ milliseconds: Int) -> String {
        if milliseconds < 1000 {
            return "\(milliseconds)ms"
        } else if milliseconds < 60000 {
            let seconds = Double(milliseconds) / 1000.0
            return String(format: "%.1fs", seconds)
        } else {
            let minutes = milliseconds / 60000
            let seconds = (milliseconds % 60000) / 1000
            return "\(minutes)m \(seconds)s"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let outputFormatter = DateFormatter()
        outputFormatter.dateStyle = .medium
        outputFormatter.timeStyle = .medium
        return outputFormatter.string(from: date)
    }
}
