import Foundation
import Testing
import TuistSupport
import XCTest

@testable import TuistServer
@testable import TuistTesting

final class ServerCredentialsStoreTests: TuistUnitTestCase {
    var subject: ServerCredentialsStore!

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_crud() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        let subject = ServerCredentialsStore(
            backend: .fileSystem,
            fileSystem: fileSystem,
            configDirectory: temporaryDirectory
        )
        let credentials = ServerCredentials(
            accessToken: "access-token", refreshToken: "refresh-token", oauthClientID: "self-hosted-client"
        )
        let serverURL = URL(string: "https://tuist.io")!

        // When
        try await subject.store(credentials: credentials, serverURL: serverURL)

        // Then
        let gotRead = try await subject.read(serverURL: serverURL)
        XCTAssertEqual(gotRead, credentials)
        try await subject.delete(serverURL: serverURL)
        let gotReadAfterDelete = try await subject.read(serverURL: serverURL)
        XCTAssertEqual(gotReadAfterDelete, nil)
    }
}

struct ServerCredentialSerializationTests {
    @Test func decodes_legacy_credentials_without_an_oauth_client() throws {
        let data = Data(#"{"accessToken":"access-token","refreshToken":"refresh-token"}"#.utf8)
        let credentials = try JSONDecoder().decode(ServerCredentials.self, from: data)

        #expect(credentials.accessToken == "access-token")
        #expect(credentials.refreshToken == "refresh-token")
        #expect(credentials.oauthClientID == nil)
    }
}
