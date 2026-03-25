import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer

protocol TestSelectiveTestingListCommandServicing {
    func run(
        fullHandle: String?,
        testRunId: String,
        path: String?,
        hitStatus: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws
}

enum TestSelectiveTestingListCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list selective testing targets because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct TestSelectiveTestingListCommandService: TestSelectiveTestingListCommandServicing {
    private let listSelectiveTestingTargetsService: ListSelectiveTestingTargetsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        listSelectiveTestingTargetsService: ListSelectiveTestingTargetsServicing = ListSelectiveTestingTargetsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.listSelectiveTestingTargetsService = listSelectiveTestingTargetsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String?,
        testRunId: String,
        path: String?,
        hitStatus: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = fullHandle ?? config.fullHandle else {
            throw TestSelectiveTestingListCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let startPage = (page ?? 1) - 1
        let pageSize = pageSize ?? 10

        let initialPage = try await listSelectiveTestingTargetsService.listSelectiveTestingTargets(
            fullHandle: resolvedFullHandle,
            serverURL: serverURL,
            testRunId: testRunId,
            hitStatus: hitStatus,
            page: startPage + 1,
            pageSize: pageSize
        )

        let targets = initialPage.targets

        if json {
            try Noora.current.json(targets)
            return
        }

        if targets.isEmpty {
            Noora.current.passthrough("No selective testing targets found for test run \(testRunId).")
            return
        }

        let totalPages = initialPage.pagination_metadata.total_pages ?? 1

        let initialRows = targets.map { target in
            [
                target.name,
                target.hit_status.rawValue,
                target.hash,
            ]
        }

        try await Noora.current.paginatedTable(
            headers: ["Name", "Status", "Hash"],
            pageSize: pageSize,
            totalPages: totalPages,
            startPage: startPage,
            loadPage: { [self] pageIndex in
                if pageIndex == startPage {
                    return initialRows
                }
                let targetPage = try await listSelectiveTestingTargetsService.listSelectiveTestingTargets(
                    fullHandle: resolvedFullHandle,
                    serverURL: serverURL,
                    testRunId: testRunId,
                    hitStatus: hitStatus,
                    page: pageIndex + 1,
                    pageSize: pageSize
                )
                return targetPage.targets.map { target in
                    [
                        target.name,
                        target.hit_status.rawValue,
                        target.hash,
                    ]
                }
            }
        )
    }
}
