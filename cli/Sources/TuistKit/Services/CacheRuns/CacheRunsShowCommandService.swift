import Foundation
import Noora
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol CacheRunsShowCommandServicing {
    func run(
        project: String?,
        runId: String,
        path: String?,
        json: Bool
    ) async throws
}

enum CacheRunsShowCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't show the cache run because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

final class CacheRunsShowCommandService: CacheRunsShowCommandServicing {
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
        project: String?,
        runId: String,
        path: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project != nil ? project! : config.fullHandle else {
            throw CacheRunsShowCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let run = try await getCacheRunService.getCacheRun(
            fullHandle: resolvedFullHandle,
            runId: runId,
            serverURL: serverURL
        )

        if json {
            try Noora.current.json(run)
            return
        }

        Noora.current.passthrough("""
            ID: \(run.id)
            Name: \(run.name)
            Status: \(run.status)
            Duration: \(run.duration)
            Ran at: \(Formatters.formatDate(Date(timeIntervalSince1970: TimeInterval(run.ran_at))))
            URL: \(run.url)
            """)
    }
}
