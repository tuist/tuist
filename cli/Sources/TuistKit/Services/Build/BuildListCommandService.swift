import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistLoader
import TuistServer
import TuistSupport

protocol BuildListCommandServicing {
    func run(
        fullHandle: String?,
        path: String?,
        gitBranch: String?,
        status: String?,
        scheme: String?,
        configuration: String?,
        tags: [String],
        values: [String],
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws
}

enum BuildListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list builds because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct BuildListCommandService: BuildListCommandServicing {
    private let listBuildsService: ListBuildsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listBuildsService: ListBuildsServicing = ListBuildsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listBuildsService = listBuildsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String?,
        path: String?,
        gitBranch: String?,
        status: String?,
        scheme: String?,
        configuration: String?,
        tags: [String],
        values: [String],
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = fullHandle ?? config.fullHandle else {
            throw BuildListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let startPage = (page ?? 1) - 1 // Convert to 0-indexed for Noora
        let pageSize = pageSize ?? 10

        let initialBuildsPage = try await listBuildsService.listBuilds(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            gitBranch: gitBranch,
            status: status,
            scheme: scheme,
            configuration: configuration,
            tags: tags,
            values: values,
            page: startPage + 1, // API uses 1-indexed pages
            pageSize: pageSize
        )

        let initialBuilds = initialBuildsPage.builds

        if json {
            try Noora.current.json(initialBuilds)
            return
        }

        if initialBuilds.isEmpty {
            var filters: [String] = []
            if let gitBranch { filters.append("branch: \(gitBranch)") }
            if let status { filters.append("status: \(status)") }
            if let scheme { filters.append("scheme: \(scheme)") }
            if let configuration { filters.append("configuration: \(configuration)") }
            if !tags.isEmpty { filters.append("tags: \(tags.joined(separator: ", "))") }
            if !values.isEmpty { filters.append("values: \(values.joined(separator: ", "))") }
            let filterDescription = filters.isEmpty ? "" : " with filters: \(filters.joined(separator: ", "))"
            if let page {
                Noora.current
                    .passthrough("No builds found on page \(page) for project \(resolvedFullHandle)\(filterDescription).")
            } else {
                Noora.current.passthrough("No builds found for project \(resolvedFullHandle)\(filterDescription).")
            }
            return
        }

        let totalPages = initialBuildsPage.pagination_metadata.total_pages ?? 1

        let initialRows = initialBuilds.map { build in
            [
                build.id,
                build.status.rawValue,
                build.scheme ?? "-",
                build.configuration ?? "-",
                formatDuration(build.duration),
                build.is_ci ? "Yes" : "No",
                formatDate(build.inserted_at),
            ]
        }

        try await Noora.current.paginatedTable(
            headers: ["ID", "Status", "Scheme", "Configuration", "Duration", "CI", "Date"],
            pageSize: pageSize,
            totalPages: totalPages,
            startPage: startPage,
            loadPage: { [self] pageIndex in
                if pageIndex == startPage {
                    return initialRows
                }

                let buildsPage = try await listBuildsService.listBuilds(
                    fullHandle: resolvedFullHandle,
                    serverURL: serverURL,
                    gitBranch: gitBranch,
                    status: status,
                    scheme: scheme,
                    configuration: configuration,
                    tags: tags,
                    values: values,
                    page: pageIndex + 1, // API uses 1-indexed pages
                    pageSize: pageSize
                )

                return buildsPage.builds.map { build in
                    [
                        build.id,
                        build.status.rawValue,
                        build.scheme ?? "-",
                        build.configuration ?? "-",
                        formatDuration(build.duration),
                        build.is_ci ? "Yes" : "No",
                        formatDate(build.inserted_at),
                    ]
                }
            }
        )
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
        outputFormatter.dateStyle = .short
        outputFormatter.timeStyle = .short
        return outputFormatter.string(from: date)
    }
}
