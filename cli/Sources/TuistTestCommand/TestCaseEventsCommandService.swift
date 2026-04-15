import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer

protocol TestCaseEventsCommandServicing {
    func run(
        project: String?,
        testCaseIdentifier: String,
        path: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws
}

enum TestCaseEventsCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't list test case events because the project is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct TestCaseEventsCommandService: TestCaseEventsCommandServicing {
    private let getTestCaseService: GetTestCaseServicing
    private let listTestCaseEventsService: ListTestCaseEventsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        getTestCaseService: GetTestCaseServicing = GetTestCaseService(),
        listTestCaseEventsService: ListTestCaseEventsServicing = ListTestCaseEventsService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.getTestCaseService = getTestCaseService
        self.listTestCaseEventsService = listTestCaseEventsService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        project: String?,
        testCaseIdentifier: String,
        path: String?,
        page: Int?,
        pageSize: Int?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project ?? config.fullHandle else {
            throw TestCaseEventsCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let testCaseId: String
        switch try TestCaseIdentifier(testCaseIdentifier) {
        case let .name(moduleName, suiteName, testName):
            let testCase = try await getTestCaseService.getTestCaseByName(
                fullHandle: resolvedFullHandle,
                moduleName: moduleName,
                name: testName,
                suiteName: suiteName,
                serverURL: serverURL
            )
            testCaseId = testCase.id
        case let .id(id):
            testCaseId = id
        }

        let result = try await listTestCaseEventsService.listTestCaseEvents(
            fullHandle: resolvedFullHandle,
            testCaseId: testCaseId,
            page: page,
            pageSize: pageSize,
            serverURL: serverURL
        )

        if json {
            try Noora.current.json(result)
            return
        }

        let info = formatEvents(result.events)
        Noora.current.passthrough("\(info)")
    }

    private func formatEvents(_ events: [ServerTestCaseEvent]) -> String {
        if events.isEmpty {
            return "No events found for this test case."
        }

        var lines: [String] = ["Events".bold()]

        for event in events {
            let timestamp = Formatters.formatTimestamp(event.inserted_at)
            let eventLabel = formatEventType(event.event_type)
            let actorLabel: String
            if let actor = event.actor {
                actorLabel = " by @\(actor.name)"
            } else {
                actorLabel = " (automatic)"
            }
            lines.append("  \(timestamp) — \(eventLabel)\(actorLabel)")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func formatEventType(_ eventType: ServerTestCaseEvent.event_typePayload) -> String {
        switch eventType {
        case .first_run: return "First run"
        case .marked_flaky: return "Marked flaky"
        case .unmarked_flaky: return "Unmarked flaky"
        case .quarantined: return "Quarantined"
        case .unquarantined: return "Unquarantined"
        }
    }
}
