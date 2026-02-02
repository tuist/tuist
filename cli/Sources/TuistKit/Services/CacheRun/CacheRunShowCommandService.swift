import Foundation
import Mockable
import Noora
import Path
import TuistLoader
import TuistServer
import TuistSupport

@Mockable
protocol CacheRunShowCommandServicing {
    func run(
        projectFullHandle: String?,
        cacheRunId: String,
        path: String?,
        json: Bool
    ) async throws
}

enum CacheRunShowCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't show the cache run because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct CacheRunShowCommandService: CacheRunShowCommandServicing {
    private let getCacheRunService: GetCacheRunServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        getCacheRunService: GetCacheRunServicing = GetCacheRunService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.getCacheRunService = getCacheRunService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        projectFullHandle: String?,
        cacheRunId: String,
        path: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = projectFullHandle ?? config.fullHandle else {
            throw CacheRunShowCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let cacheRun = try await getCacheRunService.getCacheRun(
            fullHandle: resolvedFullHandle,
            cacheRunId: cacheRunId,
            serverURL: serverURL
        )

        if json {
            try Noora.current.json(cacheRun)
            return
        }

        let cacheRunInfo = formatCacheRunInfo(cacheRun)
        Noora.current.passthrough("\(cacheRunInfo)")
    }

    func formatCacheRunInfo(_ cacheRun: CacheRun) -> String {
        var info = [
            "Cache Run".bold(),
            "ID: \(cacheRun.id)",
            "Status: \(cacheRun.status)",
            "Duration: \(Formatters.formatDuration(cacheRun.duration))",
            "CI: \(cacheRun.is_ci ? "Yes" : "No")",
            "Date: \(Formatters.formatTimestamp(cacheRun.ran_at))",
        ]

        if let tuistVersion = cacheRun.tuist_version {
            info.append("Tuist Version: \(tuistVersion)")
        }

        if let swiftVersion = cacheRun.swift_version {
            info.append("Swift Version: \(swiftVersion)")
        }

        if let macosVersion = cacheRun.macos_version {
            info.append("macOS Version: \(macosVersion)")
        }

        if let gitBranch = cacheRun.git_branch {
            info.append("Git Branch: \(gitBranch)")
        }

        if let gitCommitSha = cacheRun.git_commit_sha {
            info.append("Git Commit: \(gitCommitSha)")
        }

        if let gitRef = cacheRun.git_ref {
            info.append("Git Ref: \(gitRef)")
        }

        if let commandArguments = cacheRun.command_arguments {
            info.append("Command Arguments: \(commandArguments)")
        }

        if let cacheableTargets = cacheRun.cacheable_targets, !cacheableTargets.isEmpty {
            info.append("Cacheable Targets: \(cacheableTargets.joined(separator: ", "))")
        }

        if let localHits = cacheRun.local_cache_target_hits, !localHits.isEmpty {
            info.append("Local Cache Hits: \(localHits.joined(separator: ", "))")
        }

        if let remoteHits = cacheRun.remote_cache_target_hits, !remoteHits.isEmpty {
            info.append("Remote Cache Hits: \(remoteHits.joined(separator: ", "))")
        }

        info.append("URL: \(cacheRun.url)")

        return info.joined(separator: "\n")
    }
}
