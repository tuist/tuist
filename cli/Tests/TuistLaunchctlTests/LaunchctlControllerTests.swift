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

    @Test func bootstrap_plist() async throws {
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
        try await subject.bootstrap(plistPath: plistPath)

        // Then
        verify(commandRunner)
            .run(
                arguments: .value(
                    [
                        "/bin/launchctl",
                        "bootstrap",
                        "gui/\(uid)",
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
            .willReturn(AsyncThrowingStream { continuation in
                continuation.finish(throwing: CommandError.terminated(
                    113,
                    stderr: "Could not find service \"tuist.cache.org_project\" in domain for port",
                    command: ["/bin/launchctl", "print", "gui/501/tuist.cache.org_project"]
                ))
            })

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
            .willReturn(AsyncThrowingStream { continuation in
                continuation.finish(throwing: CommandError.terminated(
                    3,
                    stderr: "Could not find service \"tuist.cache.org_project\" in domain for port",
                    command: ["/bin/launchctl", "print", "gui/501/tuist.cache.org_project"]
                ))
            })

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
