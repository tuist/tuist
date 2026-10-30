import Foundation
import Mockable
import Testing
import TuistConfigLoader
import TuistEnvironmentTesting
import TuistNooraTesting
import TuistServer

@testable import TuistProjectCommand

struct ProjectRepositoryServiceTests {
    private let configLoader = MockConfigLoading()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let connectProjectRepositoryService = MockConnectProjectRepositoryServicing()
    private let disconnectProjectRepositoryService = MockDisconnectProjectRepositoryServicing()
    private let serverURL = URL(string: "https://test.tuist.dev")!

    init() {
        given(serverEnvironmentService).url(configServerURL: .any).willReturn(serverURL)
    }

    @Test func parsesTheRepositoryAndProject() throws {
        let connect = try ProjectRepositoryConnectCommand.parse(["acme/app", "--project", "acme/ios"])
        #expect(connect.repository == "acme/app")
        #expect(connect.project == "acme/ios")
        #expect(throws: (any Error).self) { try ProjectRepositoryConnectCommand.parse([]) }

        let disconnect = try ProjectRepositoryDisconnectCommand.parse(["-P", "acme/ios"])
        #expect(disconnect.project == "acme/ios")
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func connectsTheProjectFromTheConfigFullHandle() async throws {
        given(configLoader).loadConfig(path: .any).willReturn(.test(fullHandle: "acme/ios"))
        given(connectProjectRepositoryService).connectProjectRepository(
            fullHandle: .value("acme/ios"),
            repositoryFullHandle: .value("acme/app"),
            serverURL: .value(serverURL)
        ).willReturn("Acme/App")
        let subject = ProjectRepositoryConnectService(
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            connectProjectRepositoryService: connectProjectRepositoryService
        )

        try await subject.run(repository: "acme/app", fullHandle: nil, path: nil)

        #expect(ui().contains("The project acme/ios is linked to Acme/App"))
    }

    @Test(.withMockedEnvironment())
    func connectFailsWithoutAFullHandle() async throws {
        given(configLoader).loadConfig(path: .any).willReturn(.test(fullHandle: nil))
        let subject = ProjectRepositoryConnectService(
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            connectProjectRepositoryService: connectProjectRepositoryService
        )

        await #expect(throws: ProjectRepositoryServiceError.missingFullHandle) {
            try await subject.run(repository: "acme/app", fullHandle: nil, path: nil)
        }
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func disconnectsTheGivenProject() async throws {
        given(configLoader).loadConfig(path: .any).willReturn(.test(fullHandle: "acme/other"))
        given(disconnectProjectRepositoryService).disconnectProjectRepository(
            fullHandle: .value("acme/ios"),
            serverURL: .value(serverURL)
        ).willReturn()
        let subject = ProjectRepositoryDisconnectService(
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            disconnectProjectRepositoryService: disconnectProjectRepositoryService
        )

        try await subject.run(fullHandle: "acme/ios", path: nil)

        #expect(ui().contains("The project acme/ios is no longer linked to a repository"))
    }
}
