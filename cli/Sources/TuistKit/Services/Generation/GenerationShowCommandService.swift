import Foundation
import Mockable
import Noora
import Path
import TuistLoader
import TuistServer
import TuistSupport

@Mockable
protocol GenerationShowCommandServicing {
    func run(
        projectFullHandle: String?,
        generationId: String,
        path: String?,
        json: Bool
    ) async throws
}

enum GenerationShowCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't show the generation because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct GenerationShowCommandService: GenerationShowCommandServicing {
    private let getGenerationService: GetGenerationServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        getGenerationService: GetGenerationServicing = GetGenerationService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.getGenerationService = getGenerationService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        projectFullHandle: String?,
        generationId: String,
        path: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = projectFullHandle ?? config.fullHandle else {
            throw GenerationShowCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let generation = try await getGenerationService.getGeneration(
            fullHandle: resolvedFullHandle,
            generationId: generationId,
            serverURL: serverURL
        )

        if json {
            try Noora.current.json(generation)
            return
        }

        let generationInfo = formatGenerationInfo(generation)
        Noora.current.passthrough("\(generationInfo)")
    }

    func formatGenerationInfo(_ generation: Generation) -> String {
        var info = [
            "Generation".bold(),
            "ID: \(generation.id)",
            "Status: \(generation.status)",
            "Duration: \(Formatters.formatDuration(generation.duration))",
            "CI: \(generation.is_ci ? "Yes" : "No")",
            "Date: \(Formatters.formatTimestamp(generation.ran_at))",
        ]

        if let tuistVersion = generation.tuist_version {
            info.append("Tuist Version: \(tuistVersion)")
        }

        if let swiftVersion = generation.swift_version {
            info.append("Swift Version: \(swiftVersion)")
        }

        if let macosVersion = generation.macos_version {
            info.append("macOS Version: \(macosVersion)")
        }

        if let gitBranch = generation.git_branch {
            info.append("Git Branch: \(gitBranch)")
        }

        if let gitCommitSha = generation.git_commit_sha {
            info.append("Git Commit: \(gitCommitSha)")
        }

        if let gitRef = generation.git_ref {
            info.append("Git Ref: \(gitRef)")
        }

        if let commandArguments = generation.command_arguments {
            info.append("Command Arguments: \(commandArguments)")
        }

        if let cacheableTargets = generation.cacheable_targets, !cacheableTargets.isEmpty {
            info.append("Cacheable Targets: \(cacheableTargets.joined(separator: ", "))")
        }

        if let localHits = generation.local_cache_target_hits, !localHits.isEmpty {
            info.append("Local Cache Hits: \(localHits.joined(separator: ", "))")
        }

        if let remoteHits = generation.remote_cache_target_hits, !remoteHits.isEmpty {
            info.append("Remote Cache Hits: \(remoteHits.joined(separator: ", "))")
        }

        info.append("URL: \(generation.url)")

        return info.joined(separator: "\n")
    }
}
