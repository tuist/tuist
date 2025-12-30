import Foundation
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
            accessToken: "access-token", refreshToken: "refresh-token"
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
