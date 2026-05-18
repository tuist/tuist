import Command
import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistEnvironment
import TuistEnvironmentTesting
import TuistLoggerTesting
import TuistTesting

@testable import TuistLaunchctl

struct LaunchAgentServiceTests {
    private let subject: LaunchAgentService
    private let fileSystem = FileSystem()
    private let launchctlController = MockLaunchctlControlling()

    init() {
        subject = LaunchAgentService(
            fileSystem: fileSystem,
            launchctlController: launchctlController
        )
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_createsDirectoryAndPlist() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        given(launchctlController)
            .bootstrap(plistPath: .any)
            .willReturn()

        try await subject.setupLaunchAgent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist",
            programArguments: ["test-start"]
        )

        let homeDirectory = Environment.current.homeDirectory
        let expectedPlistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.test.plist"
        )

        let plistContent = try await fileSystem.readTextFile(at: expectedPlistPath)
        #expect(plistContent.contains("<string>tuist.test</string>"))
        #expect(plistContent.contains("<string>/usr/local/bin/tuist</string>"))
        #expect(plistContent.contains("<string>test-start</string>"))
        let stateDirectory = Environment.current.stateDirectory
        #expect(plistContent.contains("<key>StandardOutPath</key>"))
        #expect(plistContent.contains(stateDirectory.appending(component: "tuist.test.stdout.log").pathString))
        #expect(plistContent.contains("<key>StandardErrorPath</key>"))
        #expect(plistContent.contains(stateDirectory.appending(component: "tuist.test.stderr.log").pathString))

        verify(launchctlController)
            .bootstrap(plistPath: .value(expectedPlistPath))
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_includesEnvironmentVariables() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        given(launchctlController)
            .bootstrap(plistPath: .any)
            .willReturn()

        try await subject.setupLaunchAgent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist",
            programArguments: ["test-start"],
            environmentVariables: ["MY_TOKEN": "secret-123"]
        )

        let homeDirectory = Environment.current.homeDirectory
        let expectedPlistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.test.plist"
        )

        let plistContent = try await fileSystem.readTextFile(at: expectedPlistPath)
        #expect(plistContent.contains("<key>EnvironmentVariables</key>"))
        #expect(plistContent.contains("<key>MY_TOKEN</key>"))
        #expect(plistContent.contains("<string>secret-123</string>"))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_omitsEnvironmentVariablesWhenEmpty() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        given(launchctlController)
            .bootstrap(plistPath: .any)
            .willReturn()

        try await subject.setupLaunchAgent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist",
            programArguments: ["test-start"]
        )

        let homeDirectory = Environment.current.homeDirectory
        let expectedPlistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.test.plist"
        )

        let plistContent = try await fileSystem.readTextFile(at: expectedPlistPath)
        #expect(!plistContent.contains("<key>EnvironmentVariables</key>"))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_unloadsExistingPlistBeforeCreating() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        let homeDirectory = Environment.current.homeDirectory
        let expectedPlistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.test.plist"
        )

        try await fileSystem.makeDirectory(at: expectedPlistPath.parentDirectory)
        try await fileSystem.writeText("existing plist", at: expectedPlistPath)

        given(launchctlController)
            .bootout(label: .value("tuist.test"))
            .willReturn()

        given(launchctlController)
            .bootstrap(plistPath: .any)
            .willReturn()

        try await subject.setupLaunchAgent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist",
            programArguments: ["test-start"]
        )

        verify(launchctlController)
            .bootout(label: .value("tuist.test"))
            .called(1)

        verify(launchctlController)
            .bootstrap(plistPath: .value(expectedPlistPath))
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_continuesWhenUnloadFails() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        let homeDirectory = Environment.current.homeDirectory
        let expectedPlistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.test.plist"
        )

        try await fileSystem.makeDirectory(at: expectedPlistPath.parentDirectory)
        try await fileSystem.writeText("existing plist", at: expectedPlistPath)

        given(launchctlController)
            .bootout(label: .any)
            .willThrow(NSError(domain: "test", code: 1))

        given(launchctlController)
            .bootstrap(plistPath: .any)
            .willReturn()

        try await subject.setupLaunchAgent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist",
            programArguments: ["test-start"]
        )

        verify(launchctlController)
            .bootstrap(plistPath: .value(expectedPlistPath))
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_throwsWhenBootstrapFails() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        let bootstrapError = CommandError.terminated(
            78,
            stderr: "Bootstrap failed: 78: Function not implemented",
            command: ["/bin/launchctl", "bootstrap", "gui/501", "/Users/test/Library/LaunchAgents/tuist.test.plist"]
        )

        given(launchctlController)
            .bootstrap(plistPath: .any)
            .willThrow(bootstrapError)

        await #expect(
            throws: LaunchAgentServiceError
                .failedToLoadLaunchAgent(String(describing: bootstrapError))
        ) {
            try await subject.setupLaunchAgent(
                label: "tuist.test",
                plistFileName: "tuist.test.plist",
                programArguments: ["test-start"]
            )
        }
    }

    @Test(.withMockedEnvironment())
    func setupLaunchAgent_throwsWhenNoExecutablePath() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = nil

        await #expect(throws: LaunchAgentServiceError.missingExecutablePath) {
            try await subject.setupLaunchAgent(
                label: "tuist.test",
                plistFileName: "tuist.test.plist",
                programArguments: ["test-start"]
            )
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_resolvesMiseManagedBinaryPath() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        let currentMisePath = temporaryDirectory.appending(
            components: ".local", "share", "mise", "installs", "tuist", "4.0.0", "bin", "tuist"
        )
        environment.homeDirectory = temporaryDirectory
        environment.currentExecutablePathStub = currentMisePath

        let expectedBinaryPath = temporaryDirectory.appending(
            components: ".local", "share", "mise", "installs", "tuist", "latest", "tuist"
        )
        try await fileSystem.makeDirectory(at: expectedBinaryPath.parentDirectory)
        try await fileSystem.writeText("", at: expectedBinaryPath)

        given(launchctlController)
            .bootstrap(plistPath: .any)
            .willReturn()

        try await subject.setupLaunchAgent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist",
            programArguments: ["test-start"]
        )

        let homeDirectory = Environment.current.homeDirectory
        let expectedPlistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.test.plist"
        )
        let plistContent = try await fileSystem.readTextFile(at: expectedPlistPath)
        #expect(plistContent.contains(expectedBinaryPath.pathString.replacingOccurrences(of: "/private", with: "")))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_resolvesMiseManagedOldBinaryPath() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        let currentMisePath = temporaryDirectory.appending(
            components: ".local", "share", "mise", "installs", "tuist", "4.0.0", "bin", "tuist"
        )
        environment.homeDirectory = temporaryDirectory
        environment.currentExecutablePathStub = currentMisePath

        let expectedBinaryPath = temporaryDirectory.appending(
            components: ".local", "share", "mise", "installs", "tuist", "latest", "bin", "tuist"
        )
        try await fileSystem.makeDirectory(at: expectedBinaryPath.parentDirectory)
        try await fileSystem.writeText("", at: expectedBinaryPath)

        given(launchctlController)
            .bootstrap(plistPath: .any)
            .willReturn()

        try await subject.setupLaunchAgent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist",
            programArguments: ["test-start"]
        )

        let homeDirectory = Environment.current.homeDirectory
        let expectedPlistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.test.plist"
        )
        let plistContent = try await fileSystem.readTextFile(at: expectedPlistPath)
        #expect(plistContent.contains(expectedBinaryPath.pathString.replacingOccurrences(of: "/private", with: "")))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func teardownLaunchAgent_bootsOutAndRemovesPlistWhenLoaded() async throws {
        let homeDirectory = Environment.current.homeDirectory
        let plistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.test.plist"
        )
        try await fileSystem.makeDirectory(at: plistPath.parentDirectory)
        try await fileSystem.writeText("existing plist", at: plistPath)

        given(launchctlController)
            .isLoaded(label: .value("tuist.test"))
            .willReturn(true)

        given(launchctlController)
            .bootout(label: .value("tuist.test"))
            .willReturn()

        try await subject.teardownLaunchAgent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist"
        )

        verify(launchctlController)
            .bootout(label: .value("tuist.test"))
            .called(1)
        #expect(try await fileSystem.exists(plistPath) == false)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func teardownLaunchAgent_skipsBootoutWhenNotLoaded() async throws {
        let homeDirectory = Environment.current.homeDirectory
        let plistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.test.plist"
        )
        try await fileSystem.makeDirectory(at: plistPath.parentDirectory)
        try await fileSystem.writeText("existing plist", at: plistPath)

        given(launchctlController)
            .isLoaded(label: .value("tuist.test"))
            .willReturn(false)

        try await subject.teardownLaunchAgent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist"
        )

        verify(launchctlController)
            .bootout(label: .any)
            .called(0)
        #expect(try await fileSystem.exists(plistPath) == false)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func teardownLaunchAgent_propagatesBootoutErrors() async throws {
        let homeDirectory = Environment.current.homeDirectory
        let plistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.test.plist"
        )
        try await fileSystem.makeDirectory(at: plistPath.parentDirectory)
        try await fileSystem.writeText("existing plist", at: plistPath)

        let bootoutError = CommandError.terminated(
            9216,
            stderr: "Boot-out failed",
            command: ["/bin/launchctl", "bootout", "gui/501/tuist.test"]
        )

        given(launchctlController)
            .isLoaded(label: .value("tuist.test"))
            .willReturn(true)

        given(launchctlController)
            .bootout(label: .value("tuist.test"))
            .willThrow(bootoutError)

        await #expect(throws: CommandError.self) {
            try await subject.teardownLaunchAgent(
                label: "tuist.test",
                plistFileName: "tuist.test.plist"
            )
        }

        // Plist is left untouched so the user can retry without re-running setup.
        #expect(try await fileSystem.exists(plistPath) == true)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func teardownLaunchAgent_succeedsWhenPlistIsMissing() async throws {
        given(launchctlController)
            .isLoaded(label: .value("tuist.test"))
            .willReturn(false)

        try await subject.teardownLaunchAgent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist"
        )

        verify(launchctlController)
            .bootout(label: .any)
            .called(0)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_fallsBackToCurrentPathWhenMiseLatestNotFound() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        let currentMisePath = temporaryDirectory.appending(
            components: ".local", "share", "mise", "installs", "tuist", "4.0.0", "bin", "tuist"
        )
        environment.homeDirectory = temporaryDirectory
        environment.currentExecutablePathStub = currentMisePath

        given(launchctlController)
            .bootstrap(plistPath: .any)
            .willReturn()

        try await subject.setupLaunchAgent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist",
            programArguments: ["test-start"]
        )

        let homeDirectory = Environment.current.homeDirectory
        let expectedPlistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.test.plist"
        )
        let plistContent = try await fileSystem.readTextFile(at: expectedPlistPath)
        #expect(plistContent.contains(currentMisePath.pathString.replacingOccurrences(of: "/private", with: "")))
    }
}
