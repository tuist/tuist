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

/// Hands out one answer per call so a test can drive a poll to completion. The
/// last answer repeats, so an over-eager poll fails on `consumed` rather than
/// running off the end.
private final class AnswerSequence: @unchecked Sendable {
    private let lock = NSLock()
    private let answers: [Bool]
    private var index = 0

    init(answers: [Bool]) {
        self.answers = answers
    }

    var consumed: Int {
        lock.withLock { index }
    }

    func next() -> Bool {
        lock.withLock {
            defer { index += 1 }
            return answers[min(index, answers.count - 1)]
        }
    }
}

struct LaunchAgentServiceTests {
    private let subject: LaunchAgentService
    private let fileSystem = FileSystem()
    private let launchctlController = MockLaunchctlControlling()

    init() {
        subject = LaunchAgentService(
            fileSystem: fileSystem,
            launchctlController: launchctlController,
            bootoutTimeout: .milliseconds(500)
        )
        given(launchctlController)
            .isLoaded(label: .any)
            .willReturn(false)
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
        // KeepAlive must only respawn the agent on an unsuccessful (crash) exit. A clean
        // exit — e.g. when cache-proxy detects it is not authenticated — must NOT trigger a
        // respawn, otherwise launchd restarts it every ~10 seconds in an endless loop.
        #expect(plistContent.contains("<key>KeepAlive</key>"))
        #expect(plistContent.contains("<key>SuccessfulExit</key>"))
        #expect(!plistContent.contains("<key>KeepAlive</key>\n            <true/>"))

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

        launchctlController.reset()
        given(launchctlController)
            .isLoaded(label: .value("tuist.test"))
            .willReturn(true)

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
    func setupLaunchAgent_preservesExistingPlistAndThrowsWhenUnloadFails() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        let homeDirectory = Environment.current.homeDirectory
        let expectedPlistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.test.plist"
        )

        try await fileSystem.makeDirectory(at: expectedPlistPath.parentDirectory)
        try await fileSystem.writeText("existing plist", at: expectedPlistPath)

        launchctlController.reset()
        given(launchctlController)
            .isLoaded(label: .value("tuist.test"))
            .willReturn(true)

        given(launchctlController)
            .bootout(label: .any)
            .willThrow(NSError(domain: "test", code: 1))

        await #expect(throws: NSError.self) {
            try await subject.setupLaunchAgent(
                label: "tuist.test",
                plistFileName: "tuist.test.plist",
                programArguments: ["test-start"]
            )
        }

        verify(launchctlController)
            .bootstrap(plistPath: .any)
            .called(0)
        #expect(try await fileSystem.readTextFile(at: expectedPlistPath) == "existing plist")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_unloadsLoadedAgentWhenPlistIsMissing() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        launchctlController.reset()
        given(launchctlController)
            .isLoaded(label: .value("tuist.test"))
            .willReturn(true)
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
            .bootstrap(plistPath: .any)
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
    func setupLaunchAgent_usesConcreteMiseBinaryPathNotLatestSymlink() async throws {
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
        #expect(plistContent.contains(currentMisePath.pathString))
        #expect(!plistContent.contains("/installs/tuist/latest/"))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func teardownLaunchAgent_bootsOutAndRemovesPlistWhenLoaded() async throws {
        let homeDirectory = Environment.current.homeDirectory
        let plistPath = homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.test.plist"
        )
        try await fileSystem.makeDirectory(at: plistPath.parentDirectory)
        try await fileSystem.writeText("existing plist", at: plistPath)

        launchctlController.reset()
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

        launchctlController.reset()
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

        launchctlController.reset()
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
        launchctlController.reset()
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

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_succeedsWhenBootstrapIsRefusedAndTheLabelIsInTheDomain() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        launchctlController.reset()
        let answers = AnswerSequence(answers: [false, true])
        given(launchctlController)
            .isLoaded(label: .value("tuist.test"))
            .willProduce { _ in answers.next() }
        given(launchctlController)
            .bootstrap(plistPath: .any)
            .willThrow(
                CommandError.terminated(
                    5,
                    stderr: "Bootstrap failed: 5: Input/output error",
                    command: ["/bin/launchctl", "bootstrap", "gui/501", "/Users/test/Library/LaunchAgents/tuist.test.plist"]
                )
            )

        try await subject.setupLaunchAgent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist",
            programArguments: ["test-start"]
        )
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_throwsWhenBootstrapIsRefusedAndTheLabelIsAbsent() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        let bootstrapError = CommandError.terminated(
            5,
            stderr: "Bootstrap failed: 5: Input/output error",
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

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_bootstrapsOnlyOnceTheBootedOutAgentHasLeftTheDomain() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        launchctlController.reset()
        let answers = AnswerSequence(answers: [true, true, false])
        given(launchctlController)
            .isLoaded(label: .value("tuist.test"))
            .willProduce { _ in answers.next() }
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

        #expect(answers.consumed == 3)
        verify(launchctlController)
            .bootstrap(plistPath: .any)
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_bootstrapsAnywayWhenTheBootedOutAgentNeverLeavesTheDomain() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        let subject = LaunchAgentService(
            fileSystem: fileSystem,
            launchctlController: launchctlController,
            bootoutTimeout: .milliseconds(250)
        )
        launchctlController.reset()
        let answers = AnswerSequence(answers: [true])
        given(launchctlController)
            .isLoaded(label: .value("tuist.test"))
            .willProduce { _ in answers.next() }
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

        #expect(answers.consumed > 1, "the wait must poll rather than give up on the pre-bootout answer")
        verify(launchctlController)
            .bootstrap(plistPath: .any)
            .called(1)
    }

    @Test func restartLaunchAgent_kickstartsLoadedAgent() async throws {
        given(launchctlController)
            .kickstart(label: .value("tuist.test"))
            .willReturn()

        try await subject.restartLaunchAgent(label: "tuist.test")

        verify(launchctlController)
            .kickstart(label: .value("tuist.test"))
            .called(1)
    }
}
