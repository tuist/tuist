import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer

protocol BuildXcodeCASOutputListCommandServicing {
    func run(
        fullHandle: String?,
        buildId: String,
        path: String?,
        operation: String?,
        outputType: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws
}

enum BuildXcodeCASOutputListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list the build CAS outputs because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct BuildXcodeCASOutputListCommandService: BuildXcodeCASOutputListCommandServicing {
    private let listBuildCASOutputsService: ListBuildCASOutputsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listBuildCASOutputsService: ListBuildCASOutputsServicing = ListBuildCASOutputsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listBuildCASOutputsService = listBuildCASOutputsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String?,
        buildId: String,
        path: String?,
        operation: String?,
        outputType: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = fullHandle ?? config.fullHandle else {
            throw BuildXcodeCASOutputListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let startPage = (page ?? 1) - 1
        let pageSize = pageSize ?? 10

        let initialPage = try await listBuildCASOutputsService.listBuildCASOutputs(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            buildId: buildId,
            operation: operation,
            type: outputType,
            page: startPage + 1,
            pageSize: pageSize
        )

        let outputs = initialPage.outputs

        if json {
            try Noora.current.json(outputs)
            return
        }

        if outputs.isEmpty {
            Noora.current.passthrough("No CAS outputs found for build \(buildId).")
            return
        }

        let totalPages = initialPage.pagination_metadata.total_pages ?? 1

        let initialRows = outputs.map { output in
            [
                output.node_id,
                output.operation.rawValue,
                output._type?.rawValue ?? "-",
                Formatters.formatBytes(output.size),
            ]
        }

        try await Noora.current.paginatedTable(
            headers: ["Name", "Operation", "Type", "Size"],
            pageSize: pageSize,
            totalPages: totalPages,
            startPage: startPage,
            loadPage: { [self] pageIndex in
                if pageIndex == startPage {
                    return initialRows
                }
                let outputPage = try await listBuildCASOutputsService.listBuildCASOutputs(
                    fullHandle: resolvedFullHandle,
                    serverURL: serverURL,
                    buildId: buildId,
                    operation: operation,
                    type: outputType,
                    page: pageIndex + 1,
                    pageSize: pageSize
                )
                return outputPage.outputs.map { output in
                    [
                        output.node_id,
                        output.operation.rawValue,
                        output._type?.rawValue ?? "-",
                        Formatters.formatBytes(output.size),
                    ]
                }
            }
        )
    }
}
