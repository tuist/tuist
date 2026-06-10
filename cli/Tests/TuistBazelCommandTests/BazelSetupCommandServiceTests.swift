import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCAS
import TuistConfig
import TuistConfigLoader
import TuistEnvironment
import TuistEnvironmentTesting
import TuistHTTP
import TuistServer
import TuistTesting

@testable import TuistBazelCommand

struct BazelSetupCommandServiceTests {
    private let serverURL = URL(string: "https://test.tuist.dev")!
    private let cacheURL = URL(string: "https://cache.tuist.dev")!
    private let fileSystem = FileSystem()

    private func makeSubject(cacheURL: URL? = nil) -> (
        subject: BazelSetupCommandService,
        serverAuthenticationController: MockServerAuthenticationControlling,
        configLoader: MockConfigLoading
    ) {
        let serverEnvironmentService = MockServerEnvironmentServicing()
        let serverAuthenticationController = MockServerAuthenticationControlling()
        let cacheURLStore = MockCacheURLStoring()
        let configLoader = MockConfigLoading()

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(Tuist.test(fullHandle: "my-account/my-project", url: serverURL))

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(serverURL)

        given(cacheURLStore)
            .getCacheURL(for: .any, accountHandle: .value("my-account"))
            .willReturn(cacheURL ?? self.cacheURL)

        let subject = BazelSetupCommandService(
            serverEnvironmentService: serverEnvironmentService,
            serverAuthenticationController: serverAuthenticationController,
            cacheURLStore: cacheURLStore,
            fullHandleService: FullHandleService(),
            configLoader: configLoader,
            fileSystem: fileSystem
        )

        return (
            subject,
            serverAuthenticationController,
            configLoader
        )
    }

    private func credentialHelperPath() throws -> AbsolutePath {
        let environment = try #require(Environment.mocked)
        return environment.configDirectory.appending(components: ["credentials", "tuist-bazel-credential-helper"])
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_generates_bazelrc_and_credential_helper_script() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))

        // When
        try await subject.run(directory: temporaryDirectory.pathString)

        // Then
        let scriptPath = try credentialHelperPath()
        let bazelrcContent = try await fileSystem.readTextFile(
            at: temporaryDirectory.appending(component: ".bazelrc.tuist")
        )
        #expect(
            bazelrcContent == """
            build --remote_cache=grpcs://cache.tuist.dev
            build --remote_header=x-tuist-account-handle=my-account
            build --credential_helper=cache.tuist.dev=\(scriptPath.pathString)
            build --remote_instance_name=my-project

            """
        )

        let scriptContent = try await fileSystem.readTextFile(at: scriptPath)
        #expect(
            scriptContent == """
            #!/bin/sh
            exec tuist bazel credential-helper "$@"

            """
        )
        #expect(FileManager.default.isExecutableFile(atPath: scriptPath.pathString))
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_keeps_cache_endpoint_port_in_remote_cache_url() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _) = makeSubject(
            cacheURL: URL(string: "https://cache.tuist.dev:8443")!
        )
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))

        // When
        try await subject.run(directory: temporaryDirectory.pathString)

        // Then
        let scriptPath = try credentialHelperPath()
        let bazelrcContent = try await fileSystem.readTextFile(
            at: temporaryDirectory.appending(component: ".bazelrc.tuist")
        )
        #expect(bazelrcContent.contains("build --remote_cache=grpcs://cache.tuist.dev:8443"))
        #expect(bazelrcContent.contains("build --credential_helper=cache.tuist.dev=\(scriptPath.pathString)"))
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_uses_plaintext_grpc_for_http_cache_endpoints() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _) = makeSubject(
            cacheURL: URL(string: "http://localhost:5091")!
        )
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))

        // When
        try await subject.run(directory: temporaryDirectory.pathString)

        // Then
        let scriptPath = try credentialHelperPath()
        let bazelrcContent = try await fileSystem.readTextFile(
            at: temporaryDirectory.appending(component: ".bazelrc.tuist")
        )
        #expect(bazelrcContent.contains("build --remote_cache=grpc://localhost:5091"))
        #expect(bazelrcContent.contains("build --credential_helper=localhost=\(scriptPath.pathString)"))
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_does_not_overwrite_an_existing_credential_helper_script() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))

        let scriptPath = try credentialHelperPath()
        try await fileSystem.makeDirectory(at: scriptPath.parentDirectory)
        try await fileSystem.writeText("#!/bin/sh\n# custom helper\n", at: scriptPath)

        // When
        try await subject.run(directory: temporaryDirectory.pathString)

        // Then
        let scriptContent = try await fileSystem.readTextFile(at: scriptPath)
        #expect(scriptContent == "#!/bin/sh\n# custom helper\n")
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_overwrites_an_existing_bazelrc_file() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))

        let bazelrcPath = temporaryDirectory.appending(component: ".bazelrc.tuist")
        try await fileSystem.writeText("stale content", at: bazelrcPath)

        // When
        try await subject.run(directory: temporaryDirectory.pathString)

        // Then
        let bazelrcContent = try await fileSystem.readTextFile(at: bazelrcPath)
        #expect(bazelrcContent.contains("build --remote_cache=grpcs://cache.tuist.dev"))
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_throws_when_not_authenticated() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(nil)

        // When/Then
        await #expect(throws: BazelSetupCommandServiceError.notAuthenticated) {
            try await subject.run(directory: temporaryDirectory.pathString)
        }
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_throws_when_full_handle_is_missing() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, _, configLoader) = makeSubject()
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(Tuist.test(url: serverURL))

        // When/Then
        await #expect(throws: BazelSetupCommandServiceError.missingFullHandle) {
            try await subject.run(directory: temporaryDirectory.pathString)
        }
    }
}
