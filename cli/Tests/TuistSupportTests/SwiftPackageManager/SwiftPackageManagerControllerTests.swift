import FileSystem
import FileSystemTesting
import Foundation
import Testing
import struct TSCUtility.Version
import TuistConstants
import TuistEnvironment
import TuistEnvironmentTesting
import TuistTesting

@testable import TuistSupport

struct SwiftPackageManagerControllerTests {
    private let fileSystem: FileSystem
    private let commandRunner: MockCommandRunner
    private let subject: SwiftPackageManagerController

    init() {
        let fileSystem = FileSystem()
        let commandRunner = MockCommandRunner()
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
        subject = SwiftPackageManagerController(
            fileSystem: fileSystem,
            commandRunner: { commandRunner }
        )
    }

    @Test(.inTemporaryDirectory)
    func resolve() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        commandRunner.succeedCommand([
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "--replace-scm-with-registry",
            "resolve",
        ])

        // When
        try await subject.resolve(
            at: path,
            arguments: ["--replace-scm-with-registry"],
            printOutput: false
        )
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func resolve_when_fastPackageResolutionIsEnabled_usesFastPackageResolution() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        try await fileSystem.touch(path.appending(component: "Package.resolved"))
        environment.variables[Constants.EnvironmentVariables.useFastPackageResolution] = "1"
        commandRunner.succeedCommand([
            "mise",
            "x",
            "--",
            "swifterpm",
            "--package-path",
            path.pathString,
            "--scratch-path",
            path.appending(component: ".build").pathString,
            "--force-resolved-versions",
            "resolve",
        ])

        // When
        try await subject.resolve(
            at: path,
            arguments: [
                "--replace-scm-with-registry",
                "--scratch-path",
                path.appending(component: ".build").pathString,
            ],
            printOutput: false
        )
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func resolve_when_fastPackageResolutionIsEnabled_usesMiseToLookUpSwifterPM() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        environment.variables[Constants.EnvironmentVariables.useFastPackageResolution] = "yes"
        commandRunner.succeedCommand([
            "mise",
            "x",
            "--",
            "swifterpm",
            "--package-path",
            path.pathString,
            "resolve",
        ])

        // When
        try await subject.resolve(
            at: path,
            arguments: [],
            printOutput: false
        )
    }

    @Test(.inTemporaryDirectory)
    func update() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        commandRunner.succeedCommand([
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "--replace-scm-with-registry",
            "update",
        ])

        // When
        try await subject.update(
            at: path,
            arguments: ["--replace-scm-with-registry"],
            printOutput: false
        )
    }

    @Test(.inTemporaryDirectory)
    func setToolsVersion_specificVersion() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let version = try #require(Version("5.4.0"))
        commandRunner.succeedCommand([
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "tools-version",
            "--set",
            "5.4",
        ])

        // When
        try await subject.setToolsVersion(at: path, to: version)
    }

    @Test(.inTemporaryDirectory)
    func buildFatReleaseBinary() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = temporaryDirectory.appending(component: "Package")
        let product = "my-product"
        let buildPath = temporaryDirectory.appending(component: "Build")
        let outputPath = temporaryDirectory.appending(component: "Output")

        commandRunner.succeedCommand([
            "swift", "build",
            "--configuration", "release",
            "--disable-sandbox",
            "--package-path", packagePath.pathString,
            "--product", product,
            "--build-path", buildPath.pathString,
            "--triple", "arm64-apple-macosx",
        ])
        commandRunner.succeedCommand([
            "swift", "build",
            "--configuration", "release",
            "--disable-sandbox",
            "--package-path", packagePath.pathString,
            "--product", product,
            "--build-path", buildPath.pathString,
            "--triple", "x86_64-apple-macosx",
        ])

        commandRunner.succeedCommand([
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
        let outputPathIsFolder = try await fileSystem.exists(outputPath, isDirectory: true)
        #expect(outputPathIsFolder)
    }

    @Test
    func package_registry_login() async throws {
        // Given
        let command = [
            "/usr/bin/swift",
            "package-registry",
            "login",
            URL.test().appending(path: "login").absoluteString,
            "--token",
            "package-token",
            "--no-confirm",
        ]
        commandRunner.succeedCommand(command)

        // When
        try await subject.packageRegistryLogin(
            token: "package-token",
            registryURL: .test()
        )

        // Then
        #expect(commandRunner.called(command))
    }

    @Test
    func package_registry_logout() async throws {
        // Given
        let command = [
            "/usr/bin/swift",
            "package-registry",
            "logout",
            URL.test().appending(path: "logout").absoluteString,
        ]
        commandRunner.succeedCommand(command)

        // When
        try await subject.packageRegistryLogout(
            registryURL: .test()
        )

        // Then
        #expect(commandRunner.called(command))
    }
}
