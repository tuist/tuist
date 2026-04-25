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

    @Test func isLoaded_returnsTrueWhenLaunchctlPrintSucceeds() async throws {
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
        let isLoaded = try await subject.isLoaded(label: label)

        // Then
        #expect(isLoaded == true)
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

    @Test func isLoaded_returnsFalseWhenLaunchctlPrintTerminatesNonZero() async throws {
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
        let isLoaded = try await subject.isLoaded(label: label)

        // Then
        #expect(isLoaded == false)
    }

    @Test func isLoaded_propagatesNonTerminatedErrors() async throws {
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
            _ = try await subject.isLoaded(label: label)
        }
    }
}
