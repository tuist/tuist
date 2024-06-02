import MockableTest
import TSCBasic
import TuistLoader
import TuistPlugin
import TuistPluginTesting
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistKit

final class TuistServiceTests: TuistUnitTestCase {
    private var subject: TuistService!
    private var pluginService: MockPluginService!
    private var configLoader: MockConfigLoading!

    override func setUp() {
        super.setUp()
        pluginService = MockPluginService()
        configLoader = MockConfigLoading()
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
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)

        // When / Then
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
        XCTAssertNoThrow(
            try subject.run(arguments: ["command-b", "--path", projectPath.pathString], tuistBinaryPath: "")
        )
    }

    func test_run_when_command_is_global() throws {
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
        XCTAssertNoThrow(
            try subject.run(arguments: ["my-command", "argument-one"], tuistBinaryPath: "")
        )
        XCTAssertEqual(whichCommand, "tuist-my-command")
    }
}
