import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer

enum BuildGradleFailureListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list the Gradle build failures because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct BuildGradleFailureListCommandService {
    private let listGradleBuildFailuresService: ListGradleBuildFailuresServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listGradleBuildFailuresService: ListGradleBuildFailuresServicing = ListGradleBuildFailuresService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listGradleBuildFailuresService = listGradleBuildFailuresService
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
            throw BuildGradleFailureListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)
        let failures = try await listGradleBuildFailuresService.listGradleBuildFailures(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            buildId: buildId
        )

        if json {
            try Noora.current.json(failures)
            return
        }

        if failures.isEmpty {
            Noora.current.passthrough("No failed tasks or configuration steps were recorded for Gradle build \(buildId).")
            return
        }

        Noora.current.passthrough("\(format(failures))\n")
    }

    func format(_ failures: [ServerGradleBuildFailure]) -> String {
        failures.map { failure in
            let heading = failure.category == "configuration"
                ? "Configuration (\(failure.title)) \(failure.target)"
                : failure.title
            let message = failure.message
                ?? "No failure message was reported. The Tuist Gradle plugin that reported this build predates failure reporting, or the build had more failures than Tuist keeps."
            let truncation = failure.messageTruncated ? "\n(message truncated)" : ""
            return "\(heading.trimmingCharacters(in: .whitespaces))\n\(message)\(truncation)"
        }
        .joined(separator: "\n\n")
    }
}
