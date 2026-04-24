import Foundation
import Noora
import Path
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer

protocol TestCaseUpdateCommandServicing {
    func run(
        project: String?,
        testCaseIdentifier: String,
        state: ServerTestCaseState?,
        isFlaky: Bool?,
        path: String?,
        json: Bool
    ) async throws
}

enum TestCaseUpdateCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle
    case missingUpdateFields

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't update the test case because the project is missing. You can pass either its value or a path to a Tuist project."
        case .missingUpdateFields:
            return "At least one of --state or --flaky/--no-flaky must be provided."
        }
    }
}

struct TestCaseUpdateCommandService: TestCaseUpdateCommandServicing {
    private let getTestCaseService: GetTestCaseServicing
    private let updateTestCaseService: UpdateTestCaseServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        getTestCaseService: GetTestCaseServicing = GetTestCaseService(),
        updateTestCaseService: UpdateTestCaseServicing = UpdateTestCaseService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.getTestCaseService = getTestCaseService
        self.updateTestCaseService = updateTestCaseService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        project: String?,
        testCaseIdentifier: String,
        state: ServerTestCaseState?,
        isFlaky: Bool?,
        path: String?,
        json: Bool
    ) async throws {
        guard state != nil || isFlaky != nil else {
            throw TestCaseUpdateCommandServiceError.missingUpdateFields
        }

        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project ?? config.fullHandle else {
            throw TestCaseUpdateCommandServiceError.missingFullHandle
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

        let updated = try await updateTestCaseService.updateTestCase(
            fullHandle: resolvedFullHandle,
            testCaseId: testCaseId,
            state: state,
            isFlaky: isFlaky,
            serverURL: serverURL
        )

        if json {
            try Noora.current.json(updated)
            return
        }

        let info = formatUpdatedInfo(updated)
        Noora.current.passthrough("\(info)")
    }

    private func formatUpdatedInfo(_ testCase: ServerUpdatedTestCase) -> String {
        var info = [
            "Test Case".bold(),
            "Name: \(testCase.name)",
            "Module: \(testCase.module.name)",
        ]

        if let suite = testCase.suite {
            info.append("Suite: \(suite.name)")
        }

        info.append("State: \(testCase.state.rawValue)")
        info.append("Flaky: \(testCase.is_flaky ? "Yes" : "No")")
        info.append("URL: \(testCase.url)")

        return info.joined(separator: "\n") + "\n"
    }
}
