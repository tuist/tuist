import Foundation
import Noora
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol TestCasesShowCommandServicing {
    func run(
        project: String?,
        testCaseId: String,
        path: String?,
        json: Bool
    ) async throws
}

enum TestCasesShowCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't show the test case because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

final class TestCasesShowCommandService: TestCasesShowCommandServicing {
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
        project: String?,
        testCaseId: String,
        path: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project != nil ? project! : config.fullHandle else {
            throw TestCasesShowCommandServiceError.missingFullHandle
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

        Noora.current.passthrough("""
            ID: \(testCase.id)
            Name: \(testCase.name)
            Status: \(testCase.last_status)
            Last ran at: \(Formatters.formatDate(Date(timeIntervalSince1970: TimeInterval(testCase.last_ran_at))))
            URL: \(testCase.url)
            """)
    }
}
