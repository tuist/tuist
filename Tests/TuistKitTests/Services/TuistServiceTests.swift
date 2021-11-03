import TuistSupport
import TuistSupportTesting
import TuistPlugin
import TuistPluginTesting
import TuistLoaderTesting
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
            try subject.run(["my-command"]),
            TuistServiceError.taskUnavailable
        )
    }

    func test_run_when_plugin_executable() throws {
        // Given
        let pluginReleasePath = try temporaryPath()
        try fileHandler.touch(pluginReleasePath.appending(component: "tuist-command-a"))
        try fileHandler.touch(pluginReleasePath.appending(component: "tuist-command-b"))
        system.succeedCommand(pluginReleasePath.appending(component: "tuist-command-b").pathString)
        pluginService.remotePluginPathsStub = { _ in
            [
                RemotePluginPaths(
                    repositoryPath: try self.temporaryPath(),
                    releasePath: pluginReleasePath
                )
            ]
        }
        system.succeedCommand("tuist-command-b")
        
        // When/Then
        XCTAssertNoThrow(
            try subject.run(["command-b"])
        )
    }
    
    func test_run_when_command_is_global() throws {
        // Given
        var whichCommand: String?
        system.whichStub = { invokedWhichCommand in
            whichCommand = invokedWhichCommand
            return ""
        }
        system.succeedCommand("tuist-my-command", "argument-one")
        
        // When/Then
        XCTAssertNoThrow(
            try subject.run(["my-command", "argument-one"])
        )
        XCTAssertEqual(whichCommand, "tuist-my-command")
    }
}
