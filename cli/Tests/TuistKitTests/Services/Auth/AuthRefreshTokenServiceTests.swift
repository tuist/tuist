import FileSystem
import Foundation
import Path
import TuistServer
import TuistSupport
import Testing
import FileSystemTesting
import Mockable

@testable import TuistKit

struct AuthRefreshTokenServiceTests {
    
    struct TestError: LocalizedError, Equatable {}
    
    let fileSystem = FileSystem()
    let serverAuthenticationController = MockServerAuthenticationControlling()
    let subject: AuthRefreshTokenService
    
    init() {
        self.subject = AuthRefreshTokenService(serverAuthenticationController: serverAuthenticationController, fileSystem: fileSystem)
    }
    
    @Test(.inTemporaryDirectory) func run_refreshes_the_token_and_deletes_the_lockfile() async throws {
        // Given
        let urlString = "https://tuist.dev"
        let url = URL(string: urlString)!
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let lockFilePath = temporaryDirectory.appending(component: UUID().uuidString)
        try await fileSystem.touch(lockFilePath)
        given(serverAuthenticationController).lockFilePath(serverURL: .value(url)).willReturn(lockFilePath)
        given(serverAuthenticationController).refreshToken(serverURL: .value(url),
                                                           inBackground: .value(false)).willReturn()
        
        // When
        try await subject.run(serverURL: urlString)
        
        // Then
        verify(serverAuthenticationController).refreshToken(serverURL: .value(url),
                                                            inBackground: .value(false)).called(1)
        let lockFileExists = try await fileSystem.exists(lockFilePath)
        #expect(lockFileExists == false)
    }
    
    @Test(.inTemporaryDirectory) func run_deletes_the_lockfile_on_error() async throws {
        // Given
        let urlString = "https://tuist.dev"
        let url = URL(string: urlString)!
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let lockFilePath = temporaryDirectory.appending(component: UUID().uuidString)
        try await fileSystem.touch(lockFilePath)
        let error = TestError()
        given(serverAuthenticationController).lockFilePath(serverURL: .value(url)).willReturn(lockFilePath)
        given(serverAuthenticationController).refreshToken(serverURL: .value(url),
                                                           inBackground: .value(false)).willThrow(error)
        
        // When/Then
        await #expect(throws: AuthRefreshTokenServiceError.tokenRefreshFailed(error.localizedDescription), performing: {
            try await subject.run(serverURL: urlString)
        })
        let lockFileExists = try await fileSystem.exists(lockFilePath)
        #expect(lockFileExists == false)
    }
}
