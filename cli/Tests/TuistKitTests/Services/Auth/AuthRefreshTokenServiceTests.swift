import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistServer
import TuistSupport

@testable import TuistKit

struct AuthRefreshTokenServiceTests {
    struct TestError: LocalizedError, Equatable {}

    let fileSystem = FileSystem()
    let serverAuthenticationController = MockServerAuthenticationControlling()
    let subject: AuthRefreshTokenService

    init() {
        subject = AuthRefreshTokenService(serverAuthenticationController: serverAuthenticationController, fileSystem: fileSystem)
    }

    @Test(.inTemporaryDirectory) func run_refreshes_the_token_and_deletes_the_lockfile() async throws {
        // Given
        let urlString = "https://tuist.dev"
        let url = URL(string: urlString)!
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let lockFilePath = temporaryDirectory.appending(component: UUID().uuidString)
        try await fileSystem.touch(lockFilePath)
        given(serverAuthenticationController).refreshToken(
            serverURL: .value(url),
            inBackground: .value(false),
            locking: .value(false),
            forceInProcessLock: .value(false)
        ).willReturn()

        // When
        try await subject.run(serverURL: urlString)

        // Then
        verify(serverAuthenticationController).refreshToken(
            serverURL: .value(url),
            inBackground: .value(false),
            locking: .value(false),
            forceInProcessLock: .value(false)
        ).called(1)
    }
}
