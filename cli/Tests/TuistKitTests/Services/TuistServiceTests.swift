import FileSystem
import FileSystemTesting
import Mockable
import Testing
import TuistConfigLoader
import TuistLoader
import TuistPlugin
import TuistSupport
import TuistTesting

@testable import TuistKit

struct TuistServiceTests {
    private let system = MockSystem()
    private var subject: TuistService!
    private var pluginService: MockPluginService!
    private var configLoader: MockConfigLoading!

    init() {
        pluginService = MockPluginService()
        configLoader = MockConfigLoading()
        subject = TuistService(
            pluginService: pluginService,
            configLoader: configLoader
        )
    }

    @Test func run_when_command_not_found() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)

        // When / Then
        await #expect(throws: TuistServiceError.taskUnavailable) {
            try await subject.run(arguments: ["my-command"], tuistBinaryPath: "")
        }
    }

    @Test(.inTemporaryDirectory) func run_when_plugin_executable() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = path.appending(component: "Project")
        let pluginReleasePath = path.appending(component: "Plugins")
        try FileHandler.shared.touch(pluginReleasePath.appending(component: "tuist-command-a"))
        try FileHandler.shared.touch(pluginReleasePath.appending(component: "tuist-command-b"))
        system.succeedCommand([
            pluginReleasePath.appending(component: "tuist-command-b").pathString,
            "--path",
            projectPath.pathString,
        ])
        given(configLoader)
            .loadConfig(path: .value(projectPath))
            .willReturn(.default)
        pluginService.remotePluginPathsStub = { _ in
            [
                RemotePluginPaths(
                    repositoryPath: path,
                    releasePath: pluginReleasePath
                ),
            ]
        }
        system.succeedCommand(["tuist-command-b"])

        // When/Then
        try await subject.run(arguments: ["command-b", "--path", projectPath.pathString], tuistBinaryPath: "")
    }

    @Test func run_when_command_is_global() async throws {
        // Given
        var whichCommand: String?
        system.whichStub = { invokedWhichCommand in
            whichCommand = invokedWhichCommand
            return ""
        }
        system.succeedCommand(["tuist-my-command", "argument-one"])
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)

        // When/Then
        var _error: Error?
        do {
            try await subject.run(arguments: ["my-command", "argument-one"], tuistBinaryPath: "")
        } catch {
            _error = error
        }
        #expect(_error == nil)
        #expect(whichCommand == "tuist-my-command")
    }
}
