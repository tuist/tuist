import Foundation
import Noora
import Path
import TuistLoader
import TuistServer
import TuistSupport

protocol TestsShowCommandServicing {
    func run(
        project: String?,
        testId: String,
        path: String?,
        json: Bool
    ) async throws
}

enum TestsShowCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return "We couldn't show the test because the full handle is missing. You can pass either its value or a path to a Tuist project."
        }
    }
}

final class TestsShowCommandService: TestsShowCommandServicing {
    private let getTestService: GetTestServicing
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let configLoader: ConfigLoading

    init(
        getTestService: GetTestServicing = GetTestService(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        configLoader: ConfigLoading = ConfigLoader()
    ) {
        self.getTestService = getTestService
        self.serverEnvironmentService = serverEnvironmentService
        self.configLoader = configLoader
    }

    func run(
        project: String?,
        testId: String,
        path: String?,
        json: Bool
    ) async throws {
        let directoryPath: AbsolutePath = try await Environment.current.pathRelativeToWorkingDirectory(path)

        let config = try await configLoader.loadConfig(path: directoryPath)
        guard let resolvedFullHandle = project != nil ? project! : config.fullHandle else {
            throw TestsShowCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        let test = try await getTestService.getTest(
            fullHandle: resolvedFullHandle,
            testId: testId,
            serverURL: serverURL
        )

        if json {
            try Noora.current.json(test)
            return
        }

        Noora.current.passthrough("""
            ID: \(test.id)
            Status: \(test.status)
            Duration: \(test.duration)
            Ran at: \(Formatters.formatDate(Date(timeIntervalSince1970: TimeInterval(test.ran_at))))
            URL: \(test.url)
            """)
    }
}
