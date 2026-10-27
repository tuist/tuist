import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistEnvironment
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
    @Test(.inTemporaryDirectory, arguments: ["tuist.example.json", "Tuist.Example..json"])
    func hostname_aliases_preserve_rejected_and_corrupt_files(filename: String) async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let credentialsDirectory = directory.appending(component: "credentials")
        try await fileSystem.makeDirectory(at: credentialsDirectory)
        let path = credentialsDirectory.appending(component: filename)
        let subject = ServerCredentialsStore(backend: .fileSystem, fileSystem: fileSystem, configDirectory: directory)
        let environment = Environment(variables: [:], arguments: [])
        try await Environment.$current.withValue(environment) {
            let rejected = ServerCredentials(accessToken: "rejected-token", refreshToken: "refresh", rejected: true)
            try JSONEncoder().encode(rejected).write(to: URL(fileURLWithPath: path.pathString))
            for url in ["https://tuist.example", "https://TUIST.EXAMPLE."] {
                let serverURL = try #require(URL(string: url))
                #expect(try await subject.read(serverURL: serverURL) == rejected)
                try Data("corrupt-json".utf8).write(to: URL(fileURLWithPath: path.pathString))
                for _ in 0 ..< 2 {
                    await #expect(throws: ServerReportPublishingError.invalidCredentials) {
                        try await subject.read(serverURL: serverURL)
                    }
                }
                try JSONEncoder().encode(rejected).write(to: URL(fileURLWithPath: path.pathString))
            }
            let serverURL = try #require(URL(string: "https://TUIST.EXAMPLE."))
            try await subject.store(credentials: ServerCredentials(accessToken: "new-login"), serverURL: serverURL)
            #expect(try await subject.read(serverURL: serverURL)?.rejected != true)
            try await subject.delete(serverURL: serverURL)
            #expect(try await subject.read(serverURL: serverURL) == nil)
            #expect(try await !fileSystem.exists(path))
        }
    }

    @Test func decodes_legacy_credentials_without_an_oauth_client() throws {
        let data = Data(#"{"accessToken":"access-token","refreshToken":"refresh-token"}"#.utf8)
        let credentials = try JSONDecoder().decode(ServerCredentials.self, from: data)

        #expect(credentials.accessToken == "access-token")
        #expect(credentials.refreshToken == "refresh-token")
        #expect(credentials.oauthClientID == nil)
    }
}
