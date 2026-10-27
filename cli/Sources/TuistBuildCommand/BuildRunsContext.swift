import Foundation
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistServer

enum BuildRunsContextError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "The project's full handle is missing. Pass it with --project or run the command from a Tuist project that sets fullHandle."
        }
    }
}

struct BuildRunsContext {
    let fullHandle: String
    let serverURL: URL

    static func resolve(
        fullHandle: String?,
        path: String?,
        configLoader: ConfigLoading,
        serverEnvironmentService: ServerEnvironmentServicing
    ) async throws -> BuildRunsContext {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let fullHandle = fullHandle ?? config.fullHandle else {
            throw BuildRunsContextError.missingFullHandle
        }
        return BuildRunsContext(
            fullHandle: fullHandle,
            serverURL: try serverEnvironmentService.url(configServerURL: config.url)
        )
    }

    static func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    static func percentage(_ value: Double?) -> String {
        value.map { String(format: "%.1f%%", $0) } ?? "-"
    }
}
