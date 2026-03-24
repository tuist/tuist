import Command
import FileSystemTesting
import Mockable
import Testing
import TSCUtility
import TuistCore
import TuistTesting
import XcodeGraph
@testable import TuistSupport

struct SwiftPackageManagerControllerTests {
    private let subject: SwiftPackageManagerController
    private let commandRunner: MockCommandRunning
    init() {
        commandRunner = MockCommandRunning()
        subject = SwiftPackageManagerController(
            system: system,
            fileSystem: fileSystem,
            commandRunner: { commandRunner }
        )
    }

    @Test(.inTemporaryDirectory)
    func test_resolve() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        system.succeedCommand([
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "--replace-scm-with-registry",
            "resolve",
        ])

        // When / Then
        try subject.resolve(
            at: path,
            arguments: ["--replace-scm-with-registry"],
            printOutput: false
        )
    }

    @Test(.inTemporaryDirectory)
    func test_update() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        system.succeedCommand([
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "--replace-scm-with-registry",
            "update",
        ])

        // When / Then
        try subject.update(
            at: path,
            arguments: ["--replace-scm-with-registry"],
            printOutput: false
        )
    }

    @Test(.inTemporaryDirectory)
    func setToolsVersion_specificVersion() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let version = Version("5.4.0")
        system.succeedCommand([
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "tools-version",
            "--set",
            "5.4",
        ])

        // When / Then
        try subject.setToolsVersion(at: path, to: version!)
    }

    @Test(.inTemporaryDirectory)
    func test_buildFatReleaseBinary() async throws {
        // Given
        let packagePath = try #require(FileSystem.temporaryTestDirectory)
        let product = "my-product"
        let buildPath = try #require(FileSystem.temporaryTestDirectory)
        let outputPath = try #require(FileSystem.temporaryTestDirectory)

        system.succeedCommand([
            "swift", "build",
            "--configuration", "release",
            "--disable-sandbox",
            "--package-path", packagePath.pathString,
            "--product", product,
            "--build-path", buildPath.pathString,
            "--triple", "arm64-apple-macosx",
        ])
        system.succeedCommand([
            "swift", "build",
            "--configuration", "release",
            "--disable-sandbox",
            "--package-path", packagePath.pathString,
            "--product", product,
            "--build-path", buildPath.pathString,
            "--triple", "x86_64-apple-macosx",
        ])

        system.succeedCommand([
            "lipo", "-create", "-output", outputPath.appending(component: product).pathString,
            buildPath.appending(components: "arm64-apple-macosx", "release", product).pathString,
            buildPath.appending(components: "x86_64-apple-macosx", "release", product).pathString,
        ])

        // When
        try await subject.buildFatReleaseBinary(
            packagePath: packagePath,
            product: product,
            buildPath: buildPath,
            outputPath: outputPath
        )

        // Then
        // Assert that `outputPath` was created
        #expect(fileHandler.isFolder(outputPath))
    }

    @Test
    func package_registry_login() async throws {
        // Given
        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(AsyncThrowingStream(unfolding: { nil }))

        // When
        try await subject.packageRegistryLogin(
            token: "package-token",
            registryURL: .test()
        )

        // Then
        verify(commandRunner)
            .run(
                arguments: .value(
                    [
                        "/usr/bin/swift",
                        "package-registry",
                        "login",
                        URL.test().appending(path: "login").absoluteString,
                        "--token",
                        "package-token",
                        "--no-confirm",
                    ]
                ),
                environment: .any,
                workingDirectory: .any
            )
            .called(1)
    }

    @Test
    func package_registry_logout() async throws {
        // Given
        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(AsyncThrowingStream(unfolding: { nil }))

        // When
        try await subject.packageRegistryLogout(
            registryURL: .test()
        )

        // Then
        verify(commandRunner)
            .run(
                arguments: .value(
                    [
                        "/usr/bin/swift",
                        "package-registry",
                        "logout",
                        URL.test().appending(path: "logout").absoluteString,
                    ]
                ),
                environment: .any,
                workingDirectory: .any
            )
            .called(1)
    }
}
