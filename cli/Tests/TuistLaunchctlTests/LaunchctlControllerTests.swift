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

    @Test func load_plist() async throws {
        // Given
        let plistPath = try AbsolutePath(validating: "/Users/test/Library/LaunchAgents/com.example.service.plist")
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
        try await subject.load(plistPath: plistPath)

        // Then
        verify(commandRunner)
            .run(
                arguments: .value(
                    [
                        "/bin/launchctl",
                        "load",
                        plistPath.pathString,
                    ]
                ),
                environment: .any,
                workingDirectory: .any
            )
            .called(1)
    }

    @Test func unload_plist() async throws {
        // Given
        let plistPath = try AbsolutePath(validating: "/Users/test/Library/LaunchAgents/com.example.service.plist")
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
        try await subject.unload(plistPath: plistPath)

        // Then
        verify(commandRunner)
            .run(
                arguments: .value(
                    [
                        "/bin/launchctl",
                        "unload",
                        plistPath.pathString,
                    ]
                ),
                environment: .any,
                workingDirectory: .any
            )
            .called(1)
    }

    @Test func list_without_pattern() async throws {
        // Given
        let expectedOutput = """
        PID     Status  Label
        -       0       com.example.service
        1234    0       com.apple.Finder
        """

        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(
                AsyncThrowingStream { continuation in
                    continuation.yield(CommandEvent.standardOutput(Array(expectedOutput.utf8)))
                    continuation.finish()
                }
            )

        // When
        let result = try await subject.list(pattern: nil)

        // Then
        #expect(result == expectedOutput.trimmingCharacters(in: .whitespaces))

        verify(commandRunner)
            .run(
                arguments: .value(
                    [
                        "/bin/launchctl",
                        "list",
                    ]
                ),
                environment: .any,
                workingDirectory: .any
            )
            .called(1)
    }

    @Test func list_with_pattern() async throws {
        // Given
        let pattern = "com.example.*"
        let expectedOutput = """
        PID     Status  Label
        -       0       com.example.service
        5678    0       com.example.helper
        """

        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(
                AsyncThrowingStream { continuation in
                    continuation.yield(CommandEvent.standardOutput(Array(expectedOutput.utf8)))
                    continuation.finish()
                }
            )

        // When
        let result = try await subject.list(pattern: pattern)

        // Then
        #expect(result == expectedOutput.trimmingCharacters(in: .whitespaces))

        verify(commandRunner)
            .run(
                arguments: .value(
                    [
                        "/bin/launchctl",
                        "list",
                        pattern,
                    ]
                ),
                environment: .any,
                workingDirectory: .any
            )
            .called(1)
    }

    @Test func list_trims_whitespace() async throws {
        // Given
        let expectedOutput = "   PID     Status  Label\n   -       0       com.example.service   \n   "

        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(
                AsyncThrowingStream { continuation in
                    continuation.yield(CommandEvent.standardOutput(Array(expectedOutput.utf8)))
                    continuation.finish()
                }
            )

        // When
        let result = try await subject.list(pattern: nil)

        // Then
        #expect(result == expectedOutput.trimmingCharacters(in: .whitespaces))
    }

    @Test func load_propagates_errors() async throws {
        // Given
        let plistPath = try AbsolutePath(validating: "/nonexistent.plist")
        let expectedError = CommandError.terminated(1, stderr: "No such file or directory")

        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(
                AsyncThrowingStream { continuation in
                    continuation.finish(throwing: expectedError)
                }
            )

        // When/Then
        await #expect(throws: CommandError.self) {
            try await subject.load(plistPath: plistPath)
        }
    }

    @Test func unload_propagates_errors() async throws {
        // Given
        let plistPath = try AbsolutePath(validating: "/nonexistent.plist")
        let expectedError = CommandError.terminated(1, stderr: "No such file or directory")

        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(
                AsyncThrowingStream { continuation in
                    continuation.finish(throwing: expectedError)
                }
            )

        // When/Then
        await #expect(throws: CommandError.self) {
            try await subject.unload(plistPath: plistPath)
        }
    }

    @Test func list_propagates_errors() async throws {
        // Given
        let expectedError = CommandError.terminated(1, stderr: "Operation not permitted")

        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(
                AsyncThrowingStream { continuation in
                    continuation.finish(throwing: expectedError)
                }
            )

        // When/Then
        await #expect(throws: CommandError.self) {
            _ = try await subject.list(pattern: nil)
        }
    }
}
