import TSCBasic
import TuistLoaderTesting
import TuistPlugin
import TuistPluginTesting
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistKit

final class TuistServiceTests: TuistUnitTestCase {
    private var subject: TuistService!
    private var pluginService: MockPluginService!
    private var configLoader: MockConfigLoader!

    override func setUp() {
        super.setUp()
        pluginService = MockPluginService()
        configLoader = MockConfigLoader()
        subject = TuistService(
            pluginService: pluginService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        pluginService = nil
        configLoader = nil
        subject = nil
        super.tearDown()
    }

    func test_run_when_command_not_found() throws {
        XCTAssertThrowsSpecific(
            try subject.run(arguments: ["my-command"], tuistBinaryPath: ""),
            TuistServiceError.taskUnavailable
        )
    }

    func test_run_when_plugin_executable() throws {
        // Given
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project")
        let pluginReleasePath = path.appending(component: "Plugins")
        try fileHandler.touch(pluginReleasePath.appending(component: "tuist-command-a"))
        try fileHandler.touch(pluginReleasePath.appending(component: "tuist-command-b"))
        system.succeedCommand([
            pluginReleasePath.appending(component: "tuist-command-b").pathString,
            "--path",
            projectPath.pathString,
        ])
        var loadConfigPath: AbsolutePath?
        configLoader.loadConfigStub = { configPath in
            loadConfigPath = configPath
            return .default
        }
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
        XCTAssertNoThrow(
            try subject.run(arguments: ["command-b", "--path", projectPath.pathString], tuistBinaryPath: "")
        )
        XCTAssertEqual(loadConfigPath, projectPath)
    }

    func test_run_when_command_is_global() throws {
        // Given
        var whichCommand: String?
        system.whichStub = { invokedWhichCommand in
            whichCommand = invokedWhichCommand
            return ""
        }
        system.succeedCommand(["tuist-my-command", "argument-one"])

        // When/Then
        XCTAssertNoThrow(
            try subject.run(arguments: ["my-command", "argument-one"], tuistBinaryPath: "")
        )
        XCTAssertEqual(whichCommand, "tuist-my-command")
    }
}
