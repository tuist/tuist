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
import TuistREAPI
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
        configLoader: MockConfigLoading,
        remoteCacheProbeService: MockRemoteCacheProbing
    ) {
        let serverEnvironmentService = MockServerEnvironmentServicing()
        let serverAuthenticationController = MockServerAuthenticationControlling()
        let cacheURLStore = MockCacheURLStoring()
        let remoteCacheProbeService = MockRemoteCacheProbing()
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

        given(remoteCacheProbeService)
            .probe(endpoint: .any, accountHandle: .any, instanceName: .any, token: .any)
            .willReturn(())

        let subject = BazelSetupCommandService(
            serverEnvironmentService: serverEnvironmentService,
            serverAuthenticationController: serverAuthenticationController,
            cacheURLStore: cacheURLStore,
            remoteCacheProbeService: remoteCacheProbeService,
            fullHandleService: FullHandleService(),
            configLoader: configLoader,
            fileSystem: fileSystem
        )

        return (
            subject,
            serverAuthenticationController,
            configLoader,
            remoteCacheProbeService
        )
    }

    private func credentialHelperPath(from bazelrcContent: String) throws -> AbsolutePath {
        let prefix = "build --credential_helper="
        let line = try #require(
            bazelrcContent.split(whereSeparator: \.isNewline).first { $0.hasPrefix(prefix) }
        )
        let assignment = line.dropFirst(prefix.count)
        let separatorIndex = try #require(assignment.firstIndex(of: "="))
        return try AbsolutePath(validating: String(assignment[assignment.index(after: separatorIndex)...]))
    }

    private func canonicalPathString(_ path: AbsolutePath) -> String {
        URL(fileURLWithPath: path.pathString).resolvingSymlinksInPath().path
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_generates_bazelrc_and_credential_helper_script() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))
        try await fileSystem.touch(temporaryDirectory.appending(component: "MODULE.bazel"))

        // When
        try await subject.run(directory: temporaryDirectory.pathString)

        // Then
        let bazelrcContent = try await fileSystem.readTextFile(
            at: temporaryDirectory.appending(component: ".bazelrc.tuist")
        )
        let scriptPath = try credentialHelperPath(from: bazelrcContent)
        #expect(bazelrcContent.contains("build --remote_cache=grpcs://cache.tuist.dev"))
        #expect(bazelrcContent.contains("build --remote_header=x-tuist-account-handle=my-account"))
        #expect(bazelrcContent.contains("build --credential_helper=cache.tuist.dev=\(scriptPath.pathString)"))
        #expect(bazelrcContent.contains("build --remote_instance_name=my-project"))
        #expect(bazelrcContent.contains("build --bes_backend=grpcs://cache.tuist.dev"))
        #expect(bazelrcContent.contains("build --bes_header=x-tuist-account-handle=my-account"))
        #expect(bazelrcContent.contains("build --bes_header=x-tuist-project-handle=my-project"))
        #expect(bazelrcContent.contains("build --bes_timeout=30s"))
        #expect(bazelrcContent.contains("build --bes_upload_mode=fully_async"))

        #expect(
            try await fileSystem.readTextFile(at: temporaryDirectory.appending(component: ".bazelrc"))
                == "try-import %workspace%/.bazelrc.tuist\n"
        )

        let scriptContent = try await fileSystem.readTextFile(at: scriptPath)
        #expect(scriptContent.contains("project_path='"))
        #expect(scriptContent.contains("bazelrc_path='"))
        #expect(scriptContent.contains("--bazelrc-path \"$bazelrc_path\""))
        #expect(scriptContent.contains("exec tuist bazel credential-helper \"$@\""))
        #expect(FileManager.default.isExecutableFile(atPath: scriptPath.pathString))
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_keeps_cache_endpoint_port_in_remote_cache_url() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _, remoteCacheProbeService) = makeSubject(
            cacheURL: URL(string: "https://cache.tuist.dev:8443")!
        )
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))

        // When
        try await subject.run(directory: temporaryDirectory.pathString)

        // Then
        let bazelrcContent = try await fileSystem.readTextFile(
            at: temporaryDirectory.appending(component: ".bazelrc.tuist")
        )
        let scriptPath = try credentialHelperPath(from: bazelrcContent)
        #expect(bazelrcContent.contains("build --remote_cache=grpcs://cache.tuist.dev:8443"))
        #expect(bazelrcContent.contains("build --credential_helper=cache.tuist.dev=\(scriptPath.pathString)"))
        verify(remoteCacheProbeService)
            .probe(
                endpoint: .value(GRPCEndpoint(host: "cache.tuist.dev", explicitPort: 8443, isTLS: true)),
                accountHandle: .any,
                instanceName: .any,
                token: .any
            )
            .called(1)
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_uses_plaintext_grpc_for_http_cache_endpoints() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _, remoteCacheProbeService) = makeSubject(
            cacheURL: URL(string: "http://localhost:5091")!
        )
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))

        // When
        try await subject.run(directory: temporaryDirectory.pathString)

        // Then
        let bazelrcContent = try await fileSystem.readTextFile(
            at: temporaryDirectory.appending(component: ".bazelrc.tuist")
        )
        let scriptPath = try credentialHelperPath(from: bazelrcContent)
        #expect(bazelrcContent.contains("build --remote_cache=grpc://localhost:5091"))
        #expect(bazelrcContent.contains("build --credential_helper=localhost=\(scriptPath.pathString)"))
        verify(remoteCacheProbeService)
            .probe(
                endpoint: .value(GRPCEndpoint(host: "localhost", explicitPort: 5091, isTLS: false)),
                accountHandle: .any,
                instanceName: .any,
                token: .any
            )
            .called(1)
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_does_not_overwrite_an_existing_credential_helper_script() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))

        try await subject.run(directory: temporaryDirectory.pathString)
        let bazelrcContent = try await fileSystem.readTextFile(
            at: temporaryDirectory.appending(component: ".bazelrc.tuist")
        )
        let scriptPath = try credentialHelperPath(from: bazelrcContent)
        try await fileSystem.writeText("#!/bin/sh\n# custom helper\n", at: scriptPath)

        // When
        try await subject.run(directory: temporaryDirectory.pathString)

        // Then
        let scriptContent = try await fileSystem.readTextFile(at: scriptPath)
        #expect(scriptContent == "#!/bin/sh\n# custom helper\n")
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_scopes_credential_helpers_to_the_configured_checkout() async throws {
        // Given
        let firstDirectory = try #require(FileSystem.temporaryTestDirectory)
        let secondDirectory = firstDirectory.appending(component: "second-checkout")
        try await fileSystem.makeDirectory(at: secondDirectory)
        let (subject, serverAuthenticationController, _, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))

        // When
        try await subject.run(directory: firstDirectory.pathString)
        try await subject.run(directory: secondDirectory.pathString)

        // Then
        let firstHelperPath = try credentialHelperPath(
            from: try await fileSystem.readTextFile(at: firstDirectory.appending(component: ".bazelrc.tuist"))
        )
        let secondHelperPath = try credentialHelperPath(
            from: try await fileSystem.readTextFile(at: secondDirectory.appending(component: ".bazelrc.tuist"))
        )
        #expect(firstHelperPath != secondHelperPath)
        let firstHelperContent = try await fileSystem.readTextFile(at: firstHelperPath)
        let secondHelperContent = try await fileSystem.readTextFile(at: secondHelperPath)
        #expect(firstHelperContent.contains("project_path='\(canonicalPathString(firstDirectory))'"))
        #expect(!firstHelperContent.contains(canonicalPathString(secondDirectory)))
        #expect(secondHelperContent.contains("project_path='\(canonicalPathString(secondDirectory))'"))
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_adds_bazelrc_import_once() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))
        try await fileSystem.touch(temporaryDirectory.appending(component: "MODULE.bazel"))

        let bazelrcPath = temporaryDirectory.appending(component: ".bazelrc")
        try await fileSystem.writeText("build --keep_going\n", at: bazelrcPath)

        // When
        try await subject.run(directory: temporaryDirectory.pathString)
        try await subject.run(directory: temporaryDirectory.pathString)

        // Then
        #expect(
            try await fileSystem.readTextFile(at: bazelrcPath)
                == "build --keep_going\ntry-import %workspace%/.bazelrc.tuist\n"
        )
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_does_not_add_bazelrc_import_when_disabled() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))
        try await fileSystem.touch(temporaryDirectory.appending(component: "MODULE.bazel"))
        let bazelrcPath = temporaryDirectory.appending(component: ".bazelrc")
        let existingContent = "build --keep_going\n"
        try await fileSystem.writeText(existingContent, at: bazelrcPath)

        // When
        try await subject.run(directory: temporaryDirectory.pathString, addBazelrcImport: false)

        // Then
        #expect(try await fileSystem.readTextFile(at: bazelrcPath) == existingContent)
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_adds_bazelrc_import_after_content_without_a_trailing_newline() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))
        try await fileSystem.touch(temporaryDirectory.appending(component: "MODULE.bazel"))
        let bazelrcPath = temporaryDirectory.appending(component: ".bazelrc")
        try await fileSystem.writeText("build --keep_going", at: bazelrcPath)

        // When
        try await subject.run(directory: temporaryDirectory.pathString)

        // Then
        #expect(
            try await fileSystem.readTextFile(at: bazelrcPath)
                == "build --keep_going\ntry-import %workspace%/.bazelrc.tuist\n"
        )
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_recognizes_an_existing_bazelrc_import_with_flexible_whitespace() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))
        try await fileSystem.touch(temporaryDirectory.appending(component: "MODULE.bazel"))
        let bazelrcPath = temporaryDirectory.appending(component: ".bazelrc")
        let existingContent = "import  %workspace%/.bazelrc.tuist\n"
        try await fileSystem.writeText(existingContent, at: bazelrcPath)

        // When
        try await subject.run(directory: temporaryDirectory.pathString)

        // Then
        #expect(try await fileSystem.readTextFile(at: bazelrcPath) == existingContent)
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_adds_bazelrc_import_before_trailing_user_imports() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))
        try await fileSystem.touch(temporaryDirectory.appending(component: "MODULE.bazel"))
        let bazelrcPath = temporaryDirectory.appending(component: ".bazelrc")
        try await fileSystem.writeText("build --keep_going\r\ntry-import %workspace%/.bazelrc.user\r\n", at: bazelrcPath)

        // When
        try await subject.run(directory: temporaryDirectory.pathString)

        // Then
        #expect(
            try await fileSystem.readTextFile(at: bazelrcPath)
                == "build --keep_going\r\ntry-import %workspace%/.bazelrc.tuist\r\ntry-import %workspace%/.bazelrc.user\r\n"
        )
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_preserves_existing_remote_configuration() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))
        try await fileSystem.touch(temporaryDirectory.appending(component: "MODULE.bazel"))
        let bazelrcPath = temporaryDirectory.appending(component: ".bazelrc")
        let existingContent = "build --remote_cache=grpcs://example.com\n"
        try await fileSystem.writeText(existingContent, at: bazelrcPath)

        // When
        try await subject.run(directory: temporaryDirectory.pathString)

        // Then
        #expect(try await fileSystem.readTextFile(at: bazelrcPath) == existingContent)
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_preserves_existing_build_event_service_configuration() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))
        try await fileSystem.touch(temporaryDirectory.appending(component: "MODULE.bazel"))
        let bazelrcPath = temporaryDirectory.appending(component: ".bazelrc")
        let existingContent = "build --bes_backend=grpcs://example.com\n"
        try await fileSystem.writeText(existingContent, at: bazelrcPath)

        // When
        try await subject.run(directory: temporaryDirectory.pathString)

        // Then
        #expect(try await fileSystem.readTextFile(at: bazelrcPath) == existingContent)
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_ignores_commented_remote_configuration() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))
        try await fileSystem.touch(temporaryDirectory.appending(component: "MODULE.bazel"))
        let bazelrcPath = temporaryDirectory.appending(component: ".bazelrc")
        try await fileSystem.writeText("# build --remote_cache=grpcs://example.com\n", at: bazelrcPath)

        // When
        try await subject.run(directory: temporaryDirectory.pathString)

        // Then
        #expect(
            try await fileSystem.readTextFile(at: bazelrcPath)
                == "# build --remote_cache=grpcs://example.com\ntry-import %workspace%/.bazelrc.tuist\n"
        )
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_writes_bazel_configuration_at_the_workspace_root() async throws {
        // Given
        let workspaceDirectory = try #require(FileSystem.temporaryTestDirectory)
        let nestedDirectory = workspaceDirectory.appending(components: ["sources", "app"])
        try await fileSystem.makeDirectory(at: nestedDirectory)
        try await fileSystem.touch(workspaceDirectory.appending(component: "REPO.bazel"))
        let (subject, serverAuthenticationController, _, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))

        // When
        try await subject.run(directory: nestedDirectory.pathString)

        // Then
        #expect(try await fileSystem.exists(workspaceDirectory.appending(component: ".bazelrc.tuist")))
        #expect(try await fileSystem.exists(workspaceDirectory.appending(component: ".bazelrc")))
        #expect(try await !fileSystem.exists(nestedDirectory.appending(component: ".bazelrc.tuist")))
        let bazelrcContent = try await fileSystem.readTextFile(
            at: workspaceDirectory.appending(component: ".bazelrc.tuist")
        )
        let helperPath = try credentialHelperPath(from: bazelrcContent)
        let helperContent = try await fileSystem.readTextFile(at: helperPath)
        #expect(helperContent.contains("project_path='\(canonicalPathString(nestedDirectory))'"))
        #expect(helperContent.contains("bazelrc_path='\(canonicalPathString(workspaceDirectory))'"))
        #expect(helperContent.contains("--bazelrc-path \"$bazelrc_path\""))
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_creates_a_new_helper_when_the_workspace_root_changes() async throws {
        // Given
        let rootDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectDirectory = rootDirectory.appending(components: ["apps", "ios"])
        try await fileSystem.makeDirectory(at: projectDirectory)
        let nestedWorkspaceMarker = projectDirectory.appending(component: "WORKSPACE")
        try await fileSystem.touch(nestedWorkspaceMarker)
        let (subject, serverAuthenticationController, _, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))
        try await subject.run(directory: projectDirectory.pathString)
        let nestedBazelrcContent = try await fileSystem.readTextFile(
            at: projectDirectory.appending(component: ".bazelrc.tuist")
        )
        let nestedHelperPath = try credentialHelperPath(from: nestedBazelrcContent)

        try await fileSystem.remove(nestedWorkspaceMarker)
        try await fileSystem.touch(rootDirectory.appending(component: "MODULE.bazel"))

        // When
        try await subject.run(directory: projectDirectory.pathString)

        // Then
        let rootBazelrcContent = try await fileSystem.readTextFile(
            at: rootDirectory.appending(component: ".bazelrc.tuist")
        )
        let rootHelperPath = try credentialHelperPath(from: rootBazelrcContent)
        #expect(rootHelperPath != nestedHelperPath)
        #expect(
            try await fileSystem.readTextFile(at: rootHelperPath)
                .contains("bazelrc_path='\(canonicalPathString(rootDirectory))'")
        )
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_does_not_discover_a_workspace_above_the_repository_root() async throws {
        // Given
        let outerDirectory = try #require(FileSystem.temporaryTestDirectory)
        let repositoryDirectory = outerDirectory.appending(component: "repository")
        let nestedDirectory = repositoryDirectory.appending(component: "sources")
        try await fileSystem.makeDirectory(at: nestedDirectory)
        try await fileSystem.touch(outerDirectory.appending(component: "WORKSPACE"))
        try await fileSystem.touch(repositoryDirectory.appending(component: ".git"))
        let (subject, serverAuthenticationController, _, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))

        // When
        try await subject.run(directory: nestedDirectory.pathString)

        // Then
        #expect(try await fileSystem.exists(nestedDirectory.appending(component: ".bazelrc.tuist")))
        #expect(try await !fileSystem.exists(outerDirectory.appending(component: ".bazelrc.tuist")))
        #expect(try await !fileSystem.exists(repositoryDirectory.appending(component: ".bazelrc")))
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_does_not_replace_a_symbolic_bazelrc() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))
        try await fileSystem.touch(temporaryDirectory.appending(component: "MODULE.bazel"))
        let sharedBazelrcPath = temporaryDirectory.appending(component: "shared.bazelrc")
        let bazelrcPath = temporaryDirectory.appending(component: ".bazelrc")
        try await fileSystem.writeText("build --keep_going\n", at: sharedBazelrcPath)
        try await fileSystem.createSymbolicLink(from: bazelrcPath, to: sharedBazelrcPath)

        // When
        try await subject.run(directory: temporaryDirectory.pathString)

        // Then
        #expect(try await fileSystem.resolveSymbolicLink(bazelrcPath) == sharedBazelrcPath)
        #expect(try await fileSystem.readTextFile(at: sharedBazelrcPath) == "build --keep_going\n")
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_does_not_replace_a_dangling_symbolic_bazelrc() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _, _) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))
        try await fileSystem.touch(temporaryDirectory.appending(component: "MODULE.bazel"))
        let missingBazelrcPath = temporaryDirectory.appending(component: "missing.bazelrc")
        let bazelrcPath = temporaryDirectory.appending(component: ".bazelrc")
        try await fileSystem.createSymbolicLink(from: bazelrcPath, to: missingBazelrcPath)

        // When
        try await subject.run(directory: temporaryDirectory.pathString)

        // Then
        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: bazelrcPath.pathString)
                == missingBazelrcPath.pathString
        )
        #expect(try await !fileSystem.exists(missingBazelrcPath))
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_overwrites_an_existing_bazelrc_file() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _, _) = makeSubject()
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
        let (subject, serverAuthenticationController, _, _) = makeSubject()
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
        let (subject, _, configLoader, _) = makeSubject()
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(Tuist.test(url: serverURL))

        // When/Then
        await #expect(throws: BazelSetupCommandServiceError.missingFullHandle) {
            try await subject.run(directory: temporaryDirectory.pathString)
        }
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_probes_the_resolved_cache_endpoint() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _, remoteCacheProbeService) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))

        // When
        try await subject.run(directory: temporaryDirectory.pathString)

        // Then
        verify(remoteCacheProbeService)
            .probe(
                endpoint: .value(GRPCEndpoint(host: "cache.tuist.dev", explicitPort: nil, isTLS: true)),
                accountHandle: .value("my-account"),
                instanceName: .value("my-project"),
                token: .value("token")
            )
            .called(1)
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .inTemporaryDirectory)
    func run_throws_when_the_cache_endpoint_is_not_reachable() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let (subject, serverAuthenticationController, _, remoteCacheProbeService) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))
        let probeError = RemoteCacheProbeError.unavailable(
            endpoint: "cache.tuist.dev:443",
            code: "unavailable",
            message: "connection refused"
        )
        remoteCacheProbeService.reset()
        given(remoteCacheProbeService)
            .probe(endpoint: .any, accountHandle: .any, instanceName: .any, token: .any)
            .willThrow(probeError)

        // When/Then
        await #expect(throws: probeError) {
            try await subject.run(directory: temporaryDirectory.pathString)
        }

        #expect(try await !fileSystem.exists(temporaryDirectory.appending(component: ".bazelrc.tuist")))
    }
}
