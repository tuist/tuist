import FileSystem
import FileSystemTesting
import Foundation
import Path
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

    @Test(.inTemporaryDirectory) func credentials_are_only_accessible_by_their_owner() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let credentialsDirectory = directory.appending(component: "credentials")
        let subject = ServerCredentialsStore(backend: .fileSystem, fileSystem: FileSystem(), configDirectory: directory)
        let storedPath = credentialsDirectory.appending(component: "tuist.example.json")
        let legacyPath = credentialsDirectory.appending(component: "legacy.example.json")
        func permissions(_ path: AbsolutePath) throws -> Int {
            try #require(FileManager.default.attributesOfItem(atPath: path.pathString)[.posixPermissions] as? Int)
        }

        try FileManager.default.createDirectory(
            atPath: credentialsDirectory.pathString,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        try await subject.store(
            credentials: ServerCredentials(accessToken: "access-token"),
            serverURL: try #require(URL(string: "https://tuist.example"))
        )
        #expect(try permissions(credentialsDirectory) == 0o700)
        #expect(try permissions(storedPath) == 0o600)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: credentialsDirectory.pathString)
        #expect(FileManager.default.createFile(
            atPath: legacyPath.pathString,
            contents: try JSONEncoder().encode(ServerCredentials(accessToken: "legacy-token")),
            attributes: [.posixPermissions: 0o644]
        ))
        _ = try await subject.read(serverURL: try #require(URL(string: "https://legacy.example")))
        #expect(try permissions(credentialsDirectory) == 0o700)
        #expect(try permissions(legacyPath) == 0o600)
    }

    @Test(.inTemporaryDirectory, arguments: ["https://x%2F..%2F..%2F..%2Fescaped", "https://.."])
    func hosts_that_are_not_a_single_file_name_are_rejected(url: String) async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let configDirectory = directory.appending(component: "config")
        let subject = ServerCredentialsStore(backend: .fileSystem, fileSystem: FileSystem(), configDirectory: configDirectory)
        let serverURL = try #require(URL(string: url))

        let storeError = await #expect(throws: ServerCredentialsStoreError.self) {
            try await subject.store(credentials: ServerCredentials(accessToken: "access-token"), serverURL: serverURL)
        }
        let readError = await #expect(throws: ServerCredentialsStoreError.self) {
            try await subject.read(serverURL: serverURL)
        }
        for error in [storeError, readError] {
            guard case let .invalidServerURL(rejected) = error else {
                Issue.record("Expected invalidServerURL, got \(String(describing: error))")
                continue
            }
            #expect(rejected == url)
        }
        #expect(try await !FileSystem().exists(configDirectory))
        #expect(try await FileSystem().glob(directory: directory, include: ["*.json"]).collect().isEmpty)
    }

    @Test func decodes_legacy_credentials_without_an_oauth_client() throws {
        let data = Data(#"{"accessToken":"access-token","refreshToken":"refresh-token"}"#.utf8)
        let credentials = try JSONDecoder().decode(ServerCredentials.self, from: data)

        #expect(credentials.accessToken == "access-token")
        #expect(credentials.refreshToken == "refresh-token")
        #expect(credentials.oauthClientID == nil)
    }
}
