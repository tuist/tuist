import Command
import Foundation
import Mockable
import Path
import Testing

@testable import TuistLaunchctl

struct LaunchctlControllerTests {
    private let subject: LaunchctlController
    private let commandRunner = MockCommandRunning()

    init() {
        subject = LaunchctlController(
            commandRunner: commandRunner
        )
    }

    @Test(arguments: [LaunchAgentDomain.gui, .user])
    func bootstrap_plist(domain: LaunchAgentDomain) async throws {
        // Given
        let plistPath = try AbsolutePath(validating: "/Users/test/Library/LaunchAgents/com.example.service.plist")
        let uid = getuid()
        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(AsyncThrowingStream { continuation in
                continuation.finish()
            })

        // When
        try await subject.bootstrap(plistPath: plistPath, domain: domain)

        // Then
        verify(commandRunner)
            .run(
                arguments: .value(
                    [
                        "/bin/launchctl",
                        "bootstrap",
                        "\(domain.rawValue)/\(uid)",
                        plistPath.pathString,
                    ]
                ),
                environment: .any,
                workingDirectory: .any
            )
            .called(1)
    }

    @Test func bootout_label() async throws {
        // Given
        let label = "tuist.cache.org_project"
        let uid = getuid()
        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(AsyncThrowingStream { continuation in
                continuation.finish()
            })

        // When
        try await subject.bootout(label: label)

        // Then
        verify(commandRunner)
            .run(
                arguments: .value(
                    [
                        "/bin/launchctl",
                        "bootout",
                        "gui/\(uid)/\(label)",
                    ]
                ),
                environment: .any,
                workingDirectory: .any
            )
            .called(1)
    }

    @Test func kickstart_label() async throws {
        let label = "tuist.cache.org_project"
        let uid = getuid()
        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(AsyncThrowingStream { continuation in
                continuation.finish()
            })

        try await subject.kickstart(label: label)

        verify(commandRunner)
            .run(
                arguments: .value(
                    [
                        "/bin/launchctl",
                        "kickstart",
                        "-k",
                        "gui/\(uid)/\(label)",
                    ]
                ),
                environment: .any,
                workingDirectory: .any
            )
            .called(1)
    }

    @Test func job_returnsTheRunningProcessWhenLaunchctlPrintReportsOne() async throws {
        // Given
        let label = "tuist.cache.org_project"
        let uid = getuid()
        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(AsyncThrowingStream { continuation in
                continuation.yield(.standardOutput(Array(Self.printOutput(processIdentifier: 4242).utf8)))
                continuation.finish()
            })

        // When
        let job = try await subject.job(label: label)

        // Then
        #expect(job == LaunchAgentJob(processIdentifier: 4242))
        verify(commandRunner)
            .run(
                arguments: .value(
                    [
                        "/bin/launchctl",
                        "print",
                        "gui/\(uid)/\(label)",
                    ]
                ),
                environment: .any,
                workingDirectory: .any
            )
            .called(1)
    }

    @Test func job_returnsNilWhenLaunchctlPrintTerminatesNonZero() async throws {
        // Given
        let label = "tuist.cache.org_project"
        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willProduce { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.finish(throwing: CommandError.terminated(
                        113,
                        stderr: "Could not find service \"tuist.cache.org_project\" in domain for port",
                        command: ["/bin/launchctl", "print", "gui/501/tuist.cache.org_project"]
                    ))
                }
            }

        // When
        let job = try await subject.job(label: label)

        // Then
        #expect(job == nil)
    }

    @Test func job_returnsNilWhenLaunchctlPrintCannotFindTheServiceUnderAnotherCode() async throws {
        // Given
        let label = "tuist.cache.org_project"
        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willProduce { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.finish(throwing: CommandError.terminated(
                        3,
                        stderr: "Could not find service \"tuist.cache.org_project\" in domain for port",
                        command: ["/bin/launchctl", "print", "gui/501/tuist.cache.org_project"]
                    ))
                }
            }

        // When
        let job = try await subject.job(label: label)

        // Then
        #expect(job == nil)
    }

    @Test func job_propagatesTerminationsThatAreNotAMissingService() async throws {
        // Given
        let label = "tuist.cache.org_project"
        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(AsyncThrowingStream { continuation in
                continuation.finish(throwing: CommandError.terminated(
                    1,
                    stderr: "Bootstrap failed: 5: Input/output error",
                    command: ["/bin/launchctl", "print", "gui/501/tuist.cache.org_project"]
                ))
            })

        // When / Then
        await #expect(throws: CommandError.self) {
            _ = try await subject.job(label: label)
        }
    }

    @Test func job_propagatesNonTerminatedErrors() async throws {
        // Given
        let label = "tuist.cache.org_project"
        struct BoomError: Error {}
        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(AsyncThrowingStream { continuation in
                continuation.finish(throwing: BoomError())
            })

        // When / Then
        await #expect(throws: BoomError.self) {
            _ = try await subject.job(label: label)
        }
    }

    @Test func job_reportsNoProcessWhenLaunchdHoldsTheLabelWithoutOne() async throws {
        // Given: launchd prints a loaded job that is waiting to be spawned. It has
        // no `pid` line at all, which is a different answer from "not loaded" and
        // has to survive as one.
        let label = "tuist.cache.org_project"
        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(AsyncThrowingStream { continuation in
                continuation.yield(.standardOutput(Array("""
                gui/501/\(label) = {
                \tactive count = 0
                \tpath = /Users/test/Library/LaunchAgents/\(label).plist
                \ttype = LaunchAgent
                \tstate = spawn scheduled
                }
                """.utf8)))
                continuation.finish()
            })

        // When
        let job = try await subject.job(label: label)

        // Then
        #expect(job == LaunchAgentJob(processIdentifier: nil))
    }

    @Test func job_readsTheJobsOwnProcessAndNotANestedOne() async throws {
        // Given: the endpoint dictionaries launchd prints after the job carry PIDs
        // of their own, so only the first `pid` in the report is the job's.
        let label = "tuist.cache.org_project"
        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(AsyncThrowingStream { continuation in
                continuation.yield(.standardOutput(Array("""
                gui/501/\(label) = {
                \tstate = running
                \tpid = 4242
                \tendpoints = {
                \t\t"com.example" = {
                \t\t\tpid = 99
                \t\t}
                \t}
                }
                """.utf8)))
                continuation.finish()
            })

        // When
        let job = try await subject.job(label: label)

        // Then
        #expect(job == LaunchAgentJob(processIdentifier: 4242))
    }

    @Test func preferredDomain_usesGUIWhenAvailable() async throws {
        stubCommand(["/bin/launchctl", "print", "gui/\(getuid())"])

        #expect(try await subject.preferredDomain() == .gui)

        verify(commandRunner)
            .run(arguments: .value(["/bin/launchctl", "print", "user/\(getuid())"]), environment: .any, workingDirectory: .any)
            .called(0)
    }

    @Test(arguments: [
        (Int32(125), "Could not print domain: 125: Domain does not support specified action"),
        (Int32(112), "Could not find domain for user gui: 501"),
    ])
    func preferredDomain_usesBackgroundWhenGUIIsUnavailable(code: Int32, stderr: String) async throws {
        let arguments = ["/bin/launchctl", "print", "gui/\(getuid())"]
        stubCommand(arguments, error: .terminated(code, stderr: stderr, command: arguments))
        stubCommand(["/bin/launchctl", "print", "user/\(getuid())"])

        #expect(try await subject.preferredDomain() == .user)
    }

    @Test(arguments: [
        (Int32(1), "Operation not permitted"),
        (Int32(5), "Input/output error"),
        (Int32(125), "Unexpected failure"),
    ])
    func preferredDomain_preservesUnexpectedErrors(code: Int32, stderr: String) async throws {
        let arguments = ["/bin/launchctl", "print", "gui/\(getuid())"]
        let error = CommandError.terminated(code, stderr: stderr, command: arguments)
        stubCommand(arguments, error: error)

        await #expect {
            try await subject.preferredDomain()
        } throws: {
            ($0 as? CommandError)?.description == error.description
        }

        verify(commandRunner)
            .run(arguments: .value(["/bin/launchctl", "print", "user/\(getuid())"]), environment: .any, workingDirectory: .any)
            .called(0)
    }

    @Test func preferredDomain_preservesBackgroundDomainFailure() async throws {
        let gui = ["/bin/launchctl", "print", "gui/\(getuid())"]
        let user = ["/bin/launchctl", "print", "user/\(getuid())"]
        stubCommand(gui, error: .terminated(125, stderr: "Domain does not support specified action", command: gui))
        let error = CommandError.terminated(1, stderr: "Operation not permitted", command: user)
        stubCommand(user, error: error)

        await #expect {
            try await subject.preferredDomain()
        } throws: {
            ($0 as? CommandError)?.description == error.description
        }
    }

    @Test(arguments: [
        (Int32(125), "Could not print domain: 125: Domain does not support specified action"),
        (Int32(113), "Could not find service"),
    ])
    func backgroundAgent_remainsManageableWithOrWithoutGUILogin(code: Int32, stderr: String) async throws {
        let label = "tuist.cache.org_project"
        let guiTarget = "gui/\(getuid())/\(label)"
        let userTarget = "user/\(getuid())/\(label)"
        let guiPrint = ["/bin/launchctl", "print", guiTarget]
        stubCommand(guiPrint, error: .terminated(code, stderr: stderr, command: guiPrint))
        stubCommand(["/bin/launchctl", "print", userTarget], output: Self.printOutput(processIdentifier: 4242))
        stubCommand(["/bin/launchctl", "kickstart", "-k", userTarget])
        stubCommand(["/bin/launchctl", "bootout", userTarget])

        #expect(try await subject.job(label: label) == LaunchAgentJob(processIdentifier: 4242))
        try await subject.kickstart(label: label)
        try await subject.bootout(label: label)

        for arguments in [
            ["/bin/launchctl", "kickstart", "-k", userTarget],
            ["/bin/launchctl", "bootout", userTarget],
        ] {
            verify(commandRunner)
                .run(arguments: .value(arguments), environment: .any, workingDirectory: .any)
                .called(1)
        }
    }

    @Test func bootout_removesAgentsFromBothDomains() async throws {
        let label = "tuist.cache.org_project"
        for domain in ["gui", "user"] {
            let target = "\(domain)/\(getuid())/\(label)"
            stubCommand(["/bin/launchctl", "print", target], output: Self.printOutput(processIdentifier: 4242))
            stubCommand(["/bin/launchctl", "bootout", target])
        }

        try await subject.bootout(label: label)

        for domain in ["gui", "user"] {
            verify(commandRunner)
                .run(
                    arguments: .value(["/bin/launchctl", "bootout", "\(domain)/\(getuid())/\(label)"]),
                    environment: .any, workingDirectory: .any
                )
                .called(1)
        }
    }

    @Test func bootstrap_preservesErrorsInSelectedDomain() async throws {
        let path = try AbsolutePath(validating: "/Users/test/Library/LaunchAgents/tuist.test.plist")
        let arguments = ["/bin/launchctl", "bootstrap", "user/\(getuid())", path.pathString]
        let error = CommandError.terminated(5, stderr: "Input/output error", command: arguments)
        stubCommand(arguments, error: error)

        await #expect {
            try await subject.bootstrap(plistPath: path, domain: .user)
        } throws: {
            ($0 as? CommandError)?.description == error.description
        }
    }

    private func stubCommand(_ arguments: [String], output: String = "", error: CommandError? = nil) {
        given(commandRunner)
            .run(arguments: .value(arguments), environment: .any, workingDirectory: .any)
            .willProduce { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.standardOutput(Array(output.utf8)))
                    continuation.finish(throwing: error)
                }
            }
    }

    private static func printOutput(processIdentifier: Int32) -> String {
        """
        gui/501/tuist.cache.org_project = {
        \tactive count = 1
        \tstate = running
        \tpid = \(processIdentifier)
        }
        """
    }
}
