import Foundation
import Noora
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol BuildsShowCommandServicing {
    func run(
        project: String?,
        buildId: String,
        path: String?,
        json: Bool
    ) async throws
}

enum BuildsShowCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't show the build because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

final class BuildsShowCommandService: BuildsShowCommandServicing {
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
        project: String?,
        buildId: String,
        path: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project != nil ? project! : config.fullHandle else {
            throw BuildsShowCommandServiceError.missingFullHandle
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

        try Noora.current.info(.list([
            "ID: \(build.id)",
            "Status: \(build.status)",
            "Duration: \(build.duration)",
            "Ran at: \(Formatters.formatDate(Date(timeIntervalSince1970: TimeInterval(build.ran_at))))",
            "URL: \(build.url)",
        ]))
    }
}
