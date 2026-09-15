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
private final class AnswerSequence<Answer: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let answers: [Answer]
    private var index = 0

    init(answers: [Answer]) {
        self.answers = answers
    }

    var consumed: Int {
        lock.withLock { index }
    }

    func next() -> Answer {
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
            .preferredDomain()
            .willReturn(.gui)
        given(launchctlController)
            .job(label: .any)
            .willReturn(nil)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment(), arguments: [LaunchAgentDomain.gui, .user])
    func setupLaunchAgent_createsDirectoryAndPlist(domain: LaunchAgentDomain) async throws {
        resetLaunchctlController(domain: domain)
        given(launchctlController).job(label: .any).willReturn(nil)
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        given(launchctlController)
            .bootstrap(plistPath: .any, domain: .any)
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
        let plist = try #require(PropertyListSerialization.propertyList(
            from: Data(plistContent.utf8), format: nil
        ) as? [String: Any])
        #expect(plist["LimitLoadToSessionType"] as? String == (domain == .gui ? "Aqua" : "Background"))
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
            .bootstrap(plistPath: .value(expectedPlistPath), domain: .value(domain))
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_preservesExistingAgentWhenDomainLookupFails() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")
        let plistPath = Environment.current.homeDirectory.appending(
            components: "Library", "LaunchAgents", "tuist.test.plist"
        )
        try await fileSystem.makeDirectory(at: plistPath.parentDirectory)
        try await fileSystem.writeText("existing plist", at: plistPath)
        launchctlController.reset()
        given(launchctlController)
            .preferredDomain()
            .willThrow(CommandError.terminated(
                1, stderr: "Operation not permitted", command: ["/bin/launchctl", "print", "gui/501"]
            ))

        await #expect(throws: CommandError.self) {
            try await subject.setupLaunchAgent(label: "tuist.test", plistFileName: "tuist.test.plist", programArguments: [])
        }

        #expect(try await fileSystem.readTextFile(at: plistPath) == "existing plist")
        verify(launchctlController).bootout(label: .any).called(0)
        verify(launchctlController).bootstrap(plistPath: .any, domain: .any).called(0)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_includesEnvironmentVariables() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        given(launchctlController)
            .bootstrap(plistPath: .any, domain: .any)
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
            .bootstrap(plistPath: .any, domain: .any)
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

        resetLaunchctlController()
        given(launchctlController)
            .job(label: .value("tuist.test"))
            .willReturn(LaunchAgentJob(processIdentifier: 4242))

        given(launchctlController)
            .bootout(label: .value("tuist.test"))
            .willReturn()

        given(launchctlController)
            .bootstrap(plistPath: .any, domain: .any)
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
            .bootstrap(plistPath: .value(expectedPlistPath), domain: .value(.gui))
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

        resetLaunchctlController()
        given(launchctlController)
            .job(label: .value("tuist.test"))
            .willReturn(LaunchAgentJob(processIdentifier: 4242))

        given(launchctlController)
            .bootout(label: .any)
            .willThrow(NSError(domain: "test", code: 1))

        // Typed, not the raw launchctl failure: `bootout` fails for benign reasons
        // (the job already leaving, a removal still in progress) that reach the
        // user as an unreadable `CommandError` dump otherwise.
        await #expect(throws: LaunchAgentServiceError.self) {
            try await subject.setupLaunchAgent(
                label: "tuist.test",
                plistFileName: "tuist.test.plist",
                programArguments: ["test-start"]
            )
        }

        verify(launchctlController)
            .bootstrap(plistPath: .any, domain: .any)
            .called(0)
        #expect(try await fileSystem.readTextFile(at: expectedPlistPath) == "existing plist")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_unloadsLoadedAgentWhenPlistIsMissing() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        resetLaunchctlController()
        given(launchctlController)
            .job(label: .value("tuist.test"))
            .willReturn(LaunchAgentJob(processIdentifier: 4242))
        given(launchctlController)
            .bootout(label: .value("tuist.test"))
            .willReturn()
        given(launchctlController)
            .bootstrap(plistPath: .any, domain: .any)
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
            .bootstrap(plistPath: .any, domain: .any)
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
            .bootstrap(plistPath: .any, domain: .any)
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
            .bootstrap(plistPath: .any, domain: .any)
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

        resetLaunchctlController()
        given(launchctlController)
            .job(label: .value("tuist.test"))
            .willReturn(LaunchAgentJob(processIdentifier: 4242))

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

        resetLaunchctlController()
        given(launchctlController)
            .job(label: .value("tuist.test"))
            .willReturn(nil)

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

        resetLaunchctlController()
        given(launchctlController)
            .job(label: .value("tuist.test"))
            .willReturn(LaunchAgentJob(processIdentifier: 4242))

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
        resetLaunchctlController()
        given(launchctlController)
            .job(label: .value("tuist.test"))
            .willReturn(nil)

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
            .bootstrap(plistPath: .any, domain: .any)
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
    func setupLaunchAgent_succeedsWhenBootstrapIsRefusedAndAFreshProcessOwnsTheLabel() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        // A process launchd spawned after this setup booted nothing out owns the
        // label, so the refusal really is the redundant bootstrap it looks like.
        resetLaunchctlController()
        let answers = AnswerSequence<LaunchAgentJob?>(answers: [nil, LaunchAgentJob(processIdentifier: 7)])
        given(launchctlController)
            .job(label: .value("tuist.test"))
            .willProduce { _ in answers.next() }
        given(launchctlController)
            .bootstrap(plistPath: .any, domain: .any)
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
            .bootstrap(plistPath: .any, domain: .any)
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

        resetLaunchctlController()
        let answers = AnswerSequence<LaunchAgentJob?>(
            answers: [LaunchAgentJob(processIdentifier: 4242), LaunchAgentJob(processIdentifier: 4242), nil]
        )
        given(launchctlController)
            .job(label: .value("tuist.test"))
            .willProduce { _ in answers.next() }
        given(launchctlController)
            .bootout(label: .value("tuist.test"))
            .willReturn()
        given(launchctlController)
            .bootstrap(plistPath: .any, domain: .any)
            .willReturn()

        try await subject.setupLaunchAgent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist",
            programArguments: ["test-start"]
        )

        #expect(answers.consumed == 3)
        verify(launchctlController)
            .bootstrap(plistPath: .any, domain: .any)
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
        resetLaunchctlController()
        let answers = AnswerSequence<LaunchAgentJob?>(answers: [LaunchAgentJob(processIdentifier: 4242)])
        given(launchctlController)
            .job(label: .value("tuist.test"))
            .willProduce { _ in answers.next() }
        given(launchctlController)
            .bootout(label: .value("tuist.test"))
            .willReturn()
        given(launchctlController)
            .bootstrap(plistPath: .any, domain: .any)
            .willReturn()

        try await subject.setupLaunchAgent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist",
            programArguments: ["test-start"]
        )

        #expect(answers.consumed > 1, "the wait must poll rather than give up on the pre-bootout answer")
        verify(launchctlController)
            .bootstrap(plistPath: .any, domain: .any)
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

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_throwsWhenBootstrapIsRefusedAndTheOutgoingAgentStillOwnsTheLabel() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        // Given: the agent booted out above outlives the wait, so the label is
        // still in the domain under the SAME process when the bootstrap is
        // refused. Nothing bootstrapped the plist just written, and the outgoing
        // process is about to exit.
        resetLaunchctlController()
        given(launchctlController)
            .job(label: .value("tuist.test"))
            .willReturn(LaunchAgentJob(processIdentifier: 4242))
        given(launchctlController)
            .bootout(label: .value("tuist.test"))
            .willReturn()
        let bootstrapError = CommandError.terminated(
            5,
            stderr: "Bootstrap failed: 5: Input/output error",
            command: ["/bin/launchctl", "bootstrap", "gui/501", "/Users/test/Library/LaunchAgents/tuist.test.plist"]
        )
        given(launchctlController)
            .bootstrap(plistPath: .any, domain: .any)
            .willThrow(bootstrapError)

        // When / Then
        await #expect(throws: LaunchAgentServiceError.self) {
            try await subject.setupLaunchAgent(
                label: "tuist.test",
                plistFileName: "tuist.test.plist",
                programArguments: ["test-start"]
            )
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_throwsWhenBootstrapIsRefusedAndLaunchdHoldsTheLabelWithoutAProcess() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        // Given: the label is in the domain but nothing is running under it. The
        // presence of the label says the bootstrap was redundant; the missing
        // process says no configuration is serving anything.
        resetLaunchctlController()
        let answers = AnswerSequence<LaunchAgentJob?>(
            answers: [nil, LaunchAgentJob(processIdentifier: nil)]
        )
        given(launchctlController)
            .job(label: .value("tuist.test"))
            .willProduce { _ in answers.next() }
        given(launchctlController)
            .bootstrap(plistPath: .any, domain: .any)
            .willThrow(
                CommandError.terminated(
                    5,
                    stderr: "Bootstrap failed: 5: Input/output error",
                    command: ["/bin/launchctl", "bootstrap", "gui/501", "/Users/test/Library/LaunchAgents/tuist.test.plist"]
                )
            )

        // When / Then
        await #expect(throws: LaunchAgentServiceError.self) {
            try await subject.setupLaunchAgent(
                label: "tuist.test",
                plistFileName: "tuist.test.plist",
                programArguments: ["test-start"]
            )
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func setupLaunchAgent_returnsTheProcessItDisplaced() async throws {
        let environment = try #require(Environment.mocked)
        environment.currentExecutablePathStub = AbsolutePath("/usr/local/bin/tuist")

        resetLaunchctlController()
        let answers = AnswerSequence<LaunchAgentJob?>(answers: [LaunchAgentJob(processIdentifier: 4242), nil])
        given(launchctlController)
            .job(label: .value("tuist.test"))
            .willProduce { _ in answers.next() }
        given(launchctlController)
            .bootout(label: .value("tuist.test"))
            .willReturn()
        given(launchctlController)
            .bootstrap(plistPath: .any, domain: .any)
            .willReturn()

        let displaced = try await subject.setupLaunchAgent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist",
            programArguments: ["test-start"]
        )

        // The caller's readiness check needs it: whatever answers on the agent's
        // endpoint right after setup could still be this process.
        #expect(displaced == 4242)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func runningProcessIdentifier_reportsTheProcessBehindTheLabel() async throws {
        resetLaunchctlController()
        given(launchctlController)
            .job(label: .value("tuist.test"))
            .willReturn(LaunchAgentJob(processIdentifier: 7))

        #expect(await subject.runningProcessIdentifier(label: "tuist.test") == 7)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func runningProcessIdentifier_isNilWhenTheLabelIsNotInTheDomain() async throws {
        resetLaunchctlController()
        given(launchctlController)
            .job(label: .value("tuist.test"))
            .willReturn(nil)

        #expect(await subject.runningProcessIdentifier(label: "tuist.test") == nil)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func isLaunchAgentCurrent_isTrueForTheAgentSetupWouldInstallAgain() async throws {
        // Given: the agent as `setupLaunchAgent` installs it, with the plist then
        // rewritten in another key order and layout. The environment is rendered
        // from a dictionary, so two setups never agree on the text.
        let installed = try await installAgent()
        let plist = try await fileSystem.readTextFile(at: installed.plistPath)
        let propertyList = try PropertyListSerialization.propertyList(from: Data(plist.utf8), format: nil)
        let reordered = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0)
        try await fileSystem.writeText(String(decoding: reordered, as: UTF8.self), at: installed.plistPath, options: [.overwrite])
        #expect(try await fileSystem.readTextFile(at: installed.plistPath) != plist)

        // When
        let current = await service(launchedAt: Date().addingTimeInterval(1)).isLaunchAgentCurrent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist",
            programArguments: Self.programArguments,
            environmentVariables: Self.environmentVariables,
            launchInputs: [installed.launchInput]
        )

        // Then
        #expect(current)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func isLaunchAgentCurrent_isFalseWhenTheConfigurationDiffers() async throws {
        let installed = try await installAgent()
        let subject = service(launchedAt: Date().addingTimeInterval(1))

        var environmentVariables = Self.environmentVariables
        environmentVariables["TUIST_CAS_PROXY_DEVELOPER_DIR"] = "/Applications/Xcode-27.0.app/Contents/Developer"
        #expect(await !subject.isLaunchAgentCurrent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist",
            programArguments: Self.programArguments,
            environmentVariables: environmentVariables,
            launchInputs: [installed.launchInput]
        ))
        #expect(await !subject.isLaunchAgentCurrent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist",
            programArguments: Self.programArguments + ["--account", "other"],
            environmentVariables: Self.environmentVariables,
            launchInputs: [installed.launchInput]
        ))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment(), arguments: [nil, LaunchAgentJob(processIdentifier: nil)])
    func isLaunchAgentCurrent_isFalseWithoutAProcess(job: LaunchAgentJob?) async throws {
        let installed = try await installAgent()
        resetLaunchctlController()
        given(launchctlController).job(label: .value("tuist.test")).willReturn(job)

        #expect(await !service(launchedAt: Date().addingTimeInterval(1)).isLaunchAgentCurrent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist",
            programArguments: Self.programArguments,
            environmentVariables: Self.environmentVariables,
            launchInputs: [installed.launchInput]
        ))
    }

    /// A process reads its binary and its inputs when it starts, so one that
    /// started before either was replaced is running the old one, with a plist
    /// that is no different.
    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func isLaunchAgentCurrent_isFalseWhenAFileTheProcessStartedFromChangedSince() async throws {
        let installed = try await installAgent()
        let launchedAt = Date()
        let subject = service(launchedAt: launchedAt)
        let current = {
            await subject.isLaunchAgentCurrent(
                label: "tuist.test",
                plistFileName: "tuist.test.plist",
                programArguments: Self.programArguments,
                environmentVariables: Self.environmentVariables,
                launchInputs: [installed.launchInput]
            )
        }
        #expect(await current())

        try await fileSystem.writeText("the next release", at: installed.launchInput, options: [.overwrite])
        #expect(await !current(), "a replaced launch input")

        #expect(await !service(launchedAt: Date().addingTimeInterval(1)).isLaunchAgentCurrent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist",
            programArguments: Self.programArguments,
            environmentVariables: Self.environmentVariables,
            launchInputs: [installed.launchInput.parentDirectory.appending(component: "missing")]
        ), "a launch input that cannot be inspected")
    }

    /// Homebrew and most version managers switch versions by repointing a
    /// symlink at a binary installed long before. The plist names the link, and
    /// every file behind it predates the running process, so only the link
    /// shows the switch.
    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func isLaunchAgentCurrent_isFalseWhenTheBinarysSymlinkWasRepointed() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        for version in ["4.1.0", "4.2.0"] {
            let bin = temporaryDirectory.appending(components: "Cellar", version, "bin")
            try await fileSystem.makeDirectory(at: bin)
            try await fileSystem.writeText("tuist \(version)", at: bin.appending(component: "tuist"))
        }
        let link = temporaryDirectory.appending(components: "bin", "tuist")
        try await fileSystem.makeDirectory(at: link.parentDirectory)
        try FileManager.default.createSymbolicLink(atPath: link.pathString, withDestinationPath: "../Cellar/4.1.0/bin/tuist")
        let installed = try await installAgent(binary: link)
        let subject = service(launchedAt: Date())
        let isCurrent = {
            await subject.isLaunchAgentCurrent(
                label: "tuist.test",
                plistFileName: "tuist.test.plist",
                programArguments: Self.programArguments,
                environmentVariables: Self.environmentVariables,
                launchInputs: [installed.launchInput]
            )
        }
        #expect(await isCurrent())

        try FileManager.default.removeItem(atPath: link.pathString)
        try FileManager.default.createSymbolicLink(atPath: link.pathString, withDestinationPath: "../Cellar/4.2.0/bin/tuist")

        #expect(await !isCurrent())
    }

    /// The same through a directory, the way an `Xcode.app` links to a versioned
    /// Xcode.
    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func isLaunchAgentCurrent_isFalseWhenADirectorySymlinkToALaunchInputWasRepointed() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        for xcode in ["Xcode-26.5.0.app", "Xcode-27.0.0.app"] {
            let lib = temporaryDirectory.appending(components: xcode, "Contents", "Developer", "usr", "lib")
            try await fileSystem.makeDirectory(at: lib)
            try await fileSystem.writeText(xcode, at: lib.appending(component: "libToolchainCASPlugin.dylib"))
        }
        let link = temporaryDirectory.appending(component: "Xcode.app")
        try FileManager.default.createSymbolicLink(
            atPath: link.pathString,
            withDestinationPath: temporaryDirectory.appending(component: "Xcode-26.5.0.app").pathString
        )
        let plugin = link.appending(components: "Contents", "Developer", "usr", "lib", "libToolchainCASPlugin.dylib")
        _ = try await installAgent()
        let subject = service(launchedAt: Date())
        let isCurrent = {
            await subject.isLaunchAgentCurrent(
                label: "tuist.test",
                plistFileName: "tuist.test.plist",
                programArguments: Self.programArguments,
                environmentVariables: Self.environmentVariables,
                launchInputs: [plugin]
            )
        }
        #expect(await isCurrent())

        try FileManager.default.removeItem(atPath: link.pathString)
        try FileManager.default.createSymbolicLink(
            atPath: link.pathString,
            withDestinationPath: temporaryDirectory.appending(component: "Xcode-27.0.0.app").pathString
        )

        #expect(await !isCurrent())
    }

    @Test func launchDate_isWhenTheProcessStarted() throws {
        let launchedAt = try #require(LaunchAgentService.launchDate(ofProcess: getpid()))
        #expect(launchedAt <= Date())
        #expect(LaunchAgentService.launchDate(ofProcess: -1) == nil)
    }

    private static let programArguments = ["cache-proxy", "--url", "https://tuist.dev"]
    private static let environmentVariables = [
        "TUIST_FEATURE_FLAG_KURA": "1",
        "TUIST_CAS_LOG": "/tmp/cas.log",
        "TUIST_CAS_PREFETCH": "keys",
        "TUIST_TOKEN": "token",
    ]

    /// Installs `tuist.test` through `setupLaunchAgent` from `binary` (a new file
    /// when not given) and a launch input written beforehand, and leaves launchd
    /// reporting a process for it.
    private func installAgent(binary: AbsolutePath? = nil) async throws -> (plistPath: AbsolutePath, launchInput: AbsolutePath) {
        let environment = try #require(Environment.mocked)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let executable: AbsolutePath
        if let binary {
            executable = binary
        } else {
            executable = temporaryDirectory.appending(component: "tuist")
            try await fileSystem.writeText("tuist", at: executable)
        }
        let launchInput = temporaryDirectory.appending(component: "tuist-cas-proxy")
        try await fileSystem.writeText("tuist-cas-proxy", at: launchInput)
        environment.currentExecutablePathStub = executable
        given(launchctlController)
            .bootstrap(plistPath: .any, domain: .any)
            .willReturn()

        try await subject.setupLaunchAgent(
            label: "tuist.test",
            plistFileName: "tuist.test.plist",
            programArguments: Self.programArguments,
            environmentVariables: Self.environmentVariables
        )

        resetLaunchctlController()
        given(launchctlController)
            .job(label: .value("tuist.test"))
            .willReturn(LaunchAgentJob(processIdentifier: 4242))
        return (
            environment.homeDirectory.appending(components: "Library", "LaunchAgents", "tuist.test.plist"),
            launchInput
        )
    }

    private func service(launchedAt: Date) -> LaunchAgentService {
        LaunchAgentService(
            fileSystem: fileSystem,
            launchctlController: launchctlController,
            bootoutTimeout: .milliseconds(500),
            processLaunchDate: { _ in launchedAt }
        )
    }

    private func resetLaunchctlController(domain: LaunchAgentDomain = .gui) {
        launchctlController.reset()
        given(launchctlController).preferredDomain().willReturn(domain)
    }
}
