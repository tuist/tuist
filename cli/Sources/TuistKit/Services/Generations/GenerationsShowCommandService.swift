import Foundation
import Noora
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol GenerationsShowCommandServicing {
    func run(
        project: String?,
        runId: String,
        path: String?,
        json: Bool
    ) async throws
}

enum GenerationsShowCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't show the generation because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

final class GenerationsShowCommandService: GenerationsShowCommandServicing {
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
        project: String?,
        runId: String,
        path: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project != nil ? project! : config.fullHandle else {
            throw GenerationsShowCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let run = try await getGenerationService.getGeneration(
            fullHandle: resolvedFullHandle,
            runId: runId,
            serverURL: serverURL
        )

        if json {
            try Noora.current.json(run)
            return
        }

        Noora.current.passthrough("\(formatRunInfo(run))")
    }

    private func formatRunInfo(_ run: Components.Schemas.Run) -> String {
        [
            "Generation".bold(),
            "ID: \(run.id)",
            "Name: \(run.name)",
            "Duration: \(run.duration) ms",
            "Status: \(run.status)",
            "Tuist Version: \(run.tuist_version)",
            "Swift Version: \(run.swift_version)",
            "macOS Version: \(run.macos_version)",
            "Ran at: \(Formatters.formatDate(Date(timeIntervalSince1970: TimeInterval(run.ran_at))))",
            "URL: \(run.url)",
        ]
        .joined(separator: "\n")
    }
}
