import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistSupport

@testable import TuistServer
@testable import TuistTesting

struct ServerCredentialsStoreTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory)
    func crud() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let subject = ServerCredentialsStore(
            backend: .fileSystem,
            fileSystem: fileSystem,
            configDirectory: temporaryDirectory
        )
        let credentials = ServerCredentials(
            accessToken: "access-token", refreshToken: "refresh-token"
        )
        let serverURL = URL(string: "https://tuist.io")!

        // When
        try await subject.store(credentials: credentials, serverURL: serverURL)

        // Then
        let gotRead = try await subject.read(serverURL: serverURL)
        #expect(gotRead == credentials)
        try await subject.delete(serverURL: serverURL)
        let gotReadAfterDelete = try await subject.read(serverURL: serverURL)
        #expect(gotReadAfterDelete == nil)
    }
}
