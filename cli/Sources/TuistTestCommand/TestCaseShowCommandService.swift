import Foundation
import Noora
import Path
import TuistEnvironment
import TuistLoader
import TuistServer
import TuistSupport

protocol TestCaseShowCommandServicing {
    func run(
        fullHandle: String?,
        testCaseId: String,
        path: String?,
        json: Bool
    ) async throws
}

enum TestCaseShowCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't show the test case because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

struct TestCaseShowCommandService: TestCaseShowCommandServicing {
    private let getTestCaseService: GetTestCaseServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        getTestCaseService: GetTestCaseServicing = GetTestCaseService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.getTestCaseService = getTestCaseService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        fullHandle: String?,
        testCaseId: String,
        path: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = fullHandle ?? config.fullHandle else {
            throw TestCaseShowCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let testCase = try await getTestCaseService.getTestCase(
            fullHandle: resolvedFullHandle,
            testCaseId: testCaseId,
            serverURL: serverURL
        )

        if json {
            try Noora.current.json(testCase)
            return
        }

        let info = formatTestCaseInfo(testCase)
        Noora.current.passthrough("\(info)")
    }

    private func formatTestCaseInfo(_ testCase: ServerTestCase) -> String {
        var info = [
            "Test Case".bold(),
            "Name: \(testCase.name)",
            "Module: \(testCase.module.name)",
        ]

        if let suite = testCase.suite {
            info.append("Suite: \(suite.name)")
        }

        info.append("Flaky: \(testCase.is_flaky ? "Yes" : "No")")
        info.append("Quarantined: \(testCase.is_quarantined ? "Yes" : "No")")

        info.append("")
        info.append("Metrics".bold())

        if let reliabilityRate = testCase.reliability_rate {
            info.append("Reliability: \(String(format: "%.1f", reliabilityRate))%")
        }

        info.append("Flakiness Rate: \(String(format: "%.1f", testCase.flakiness_rate))%")
        info.append("Total Runs: \(testCase.total_runs)")
        info.append("Failed Runs: \(testCase.failed_runs)")
        info.append("Avg Duration: \(Formatters.formatDuration(testCase.avg_duration))")

        info.append("")
        info.append("Last Run".bold())
        info.append("Status: \(testCase.last_status.rawValue)")
        info.append("Duration: \(Formatters.formatDuration(testCase.last_duration))")
        info.append("Ran At: \(Formatters.formatTimestamp(testCase.last_ran_at))")

        return info.joined(separator: "\n")
    }
}
