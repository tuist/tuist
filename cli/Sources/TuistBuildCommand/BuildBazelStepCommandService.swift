import Foundation
import Noora
import TuistConfigLoader
import TuistNooraExtension
import TuistServer

struct BuildBazelStepListCommandService {
    private let bazelInvocationsService: BazelInvocationsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        bazelInvocationsService: BazelInvocationsServicing = BazelInvocationsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.bazelInvocationsService = bazelInvocationsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String?,
        invocationId: String,
        path: String?,
        status: String?,
        target: String?,
        search: String?,
        sortBy: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        let context = try await BuildRunsContext.resolve(
            fullHandle: fullHandle,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService
        )
        let startPage = (page ?? 1) - 1
        let pageSize = pageSize ?? 10

        let fetch = { (pageIndex: Int) in
            try await bazelInvocationsService.listBazelBuildSteps(
                fullHandle: context.fullHandle,
                serverURL: context.serverURL,
                invocationId: invocationId,
                status: status,
                target: target,
                search: search,
                sortBy: sortBy,
                page: pageIndex + 1,
                pageSize: pageSize
            )
        }

        let initialPage = try await fetch(startPage)

        if json {
            try Noora.current.json(initialPage)
            return
        }

        if initialPage.steps.isEmpty {
            let message = initialPage.availability == .processing
                ? "The steps of Bazel invocation \(invocationId) are still being processed."
                : "No steps found for Bazel invocation \(invocationId)."
            Noora.current.passthrough("\(message)")
            return
        }

        try await Noora.current.paginatedTable(
            headers: ["ID", "Title", "Target", "Status", "Duration"],
            pageSize: pageSize,
            totalPages: initialPage.pagination_metadata.total_pages ?? 1,
            startPage: startPage,
            loadPage: { pageIndex in
                let page = pageIndex == startPage ? initialPage : try await fetch(pageIndex)
                return page.steps.map(Self.row)
            }
        )
    }

    private static func row(_ step: Operations.listBazelBuildSteps.Output.Ok.Body.jsonPayload.stepsPayloadPayload) -> [String] {
        [
            step.id,
            step.title,
            step.target.isEmpty ? "-" : step.target,
            step.status,
            Formatters.formatDuration(Int(step.duration_ms)),
        ]
    }
}

struct BuildBazelStepShowCommandService {
    private let bazelInvocationsService: BazelInvocationsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        bazelInvocationsService: BazelInvocationsServicing = BazelInvocationsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.bazelInvocationsService = bazelInvocationsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(fullHandle: String?, invocationId: String, stepId: String, path: String?, json: Bool) async throws {
        let context = try await BuildRunsContext.resolve(
            fullHandle: fullHandle,
            path: path,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService
        )
        let step = try await bazelInvocationsService.getBazelBuildStep(
            fullHandle: context.fullHandle,
            serverURL: context.serverURL,
            invocationId: invocationId,
            stepId: stepId
        )

        if json {
            try Noora.current.json(step)
            return
        }

        var info = [
            "Bazel step".bold(),
            "ID: \(step.id)",
            "Title: \(step.title)",
            "Category: \(step.category)",
            "Status: \(step.status)",
            "Duration: \(Formatters.formatDuration(Int(step.duration_ms)))",
        ]
        if !step.target.isEmpty { info.append("Target: \(step.target)") }

        info.append("")
        info.append("Log".bold())
        if let log = step.log, !log.isEmpty {
            info.append(log.hasSuffix("\n") ? String(log.dropLast()) : log)
            if step.log_truncated {
                info.append("The log was truncated.")
            }
        } else {
            info.append("The step published no log.")
        }

        Noora.current.passthrough("\(info.joined(separator: "\n"))")
    }
}
