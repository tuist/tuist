import Command
import Foundation
import Mockable
import Testing

@testable import TuistSupport

struct SecurityControllerTests {
    private let subject: SecurityController
    private let commandRunner = MockCommandRunning()

    init() {
        subject = SecurityController(
            commandRunner: commandRunner
        )
    }

    @Test func add_internet_password() async throws {
        // Given
        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(AsyncThrowingStream(unfolding: { nil }))

        // When
        try await subject.addInternetPassword(
            accountName: "account",
            serverName: "tuist.dev",
            password: "password",
            securityProtocol: .https,
            update: true,
            applications: ["/App"]
        )

        // Then
        verify(commandRunner)
            .run(
                arguments: .value(
                    [
                        "/usr/bin/security",
                        "add-internet-password",
                        "-a", "account",
                        "-s", "tuist.dev",
                        "-w", "password",
                        "-r", "htps",
                        "-U",
                        "-T", "/App",
                    ]
                ),
                environment: .any,
                workingDirectory: .any
            )
            .called(1)
    }
}
