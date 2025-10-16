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
}
