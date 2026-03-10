import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistServer

protocol BuildIssueListCommandServicing {
    func run(
        fullHandle: String?,
        buildId: String,
        path: String?,
        json: Bool
    ) async throws
}

enum BuildIssueListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list the build issues because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct BuildIssueListCommandService: BuildIssueListCommandServicing {
    private let listBuildIssuesService: ListBuildIssuesServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listBuildIssuesService: ListBuildIssuesServicing = ListBuildIssuesService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listBuildIssuesService = listBuildIssuesService
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
            throw BuildIssueListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let result = try await listBuildIssuesService.listBuildIssues(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            buildId: buildId,
            type: nil,
            target: nil,
            stepType: nil
        )

        let issues = result.issues

        if json {
            try Noora.current.json(issues)
            return
        }

        if issues.isEmpty {
            Noora.current.passthrough("No issues found for build \(buildId).")
            return
        }

        let lines = issues.map { issue in
            let type = issue._type.rawValue
            let message = issue.message ?? issue.title
            let target = issue.target
            let filePath = issue.path ?? "-"
            return "[\(type)] \(message) (target: \(target), file: \(filePath))"
        }

        Noora.current.passthrough("\(lines.joined(separator: "\n"))")
    }
}
