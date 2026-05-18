import Command
import TSCUtility
import TuistCore
import TuistTesting
import XcodeGraph
import XCTest
@testable import TuistSupport

final class SwiftPackageManagerControllerTests: TuistUnitTestCase {
    private var subject: SwiftPackageManagerController!

    override func setUp() {
        super.setUp()

        subject = SwiftPackageManagerController(
            fileSystem: fileSystem,
            commandRunner: { self.mockCommandRunner }
        )
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }

    func test_resolve() async throws {
        // Given
        let path = try temporaryPath()
        mockCommandRunner.succeedCommand([
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

    func test_update() async throws {
        // Given
        let path = try temporaryPath()
        mockCommandRunner.succeedCommand([
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

    func test_setToolsVersion_specificVersion() async throws {
        // Given
        let path = try temporaryPath()
        let version = Version("5.4.0")
        mockCommandRunner.succeedCommand([
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "tools-version",
            "--set",
            "5.4",
        ])

        // When
        try await subject.setToolsVersion(at: path, to: version!)
    }

    func test_buildFatReleaseBinary() async throws {
        // Given
        let packagePath = try temporaryPath()
        let product = "my-product"
        let buildPath = try temporaryPath()
        let outputPath = try temporaryPath()

        mockCommandRunner.succeedCommand([
            "swift", "build",
            "--configuration", "release",
            "--disable-sandbox",
            "--package-path", packagePath.pathString,
            "--product", product,
            "--build-path", buildPath.pathString,
            "--triple", "arm64-apple-macosx",
        ])
        mockCommandRunner.succeedCommand([
            "swift", "build",
            "--configuration", "release",
            "--disable-sandbox",
            "--package-path", packagePath.pathString,
            "--product", product,
            "--build-path", buildPath.pathString,
            "--triple", "x86_64-apple-macosx",
        ])

        mockCommandRunner.succeedCommand([
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
        let outputPathIsFolder = try await fileSystem.exists(outputPath, isDirectory: true)
        XCTAssertTrue(outputPathIsFolder)
    }

    func test_package_registry_login() async throws {
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
        mockCommandRunner.succeedCommand(command)

        // When
        try await subject.packageRegistryLogin(
            token: "package-token",
            registryURL: .test()
        )

        // Then
        XCTAssertTrue(mockCommandRunner.called(command))
    }

    func test_package_registry_logout() async throws {
        // Given
        let command = [
            "/usr/bin/swift",
            "package-registry",
            "logout",
            URL.test().appending(path: "logout").absoluteString,
        ]
        mockCommandRunner.succeedCommand(command)

        // When
        try await subject.packageRegistryLogout(
            registryURL: .test()
        )

        // Then
        XCTAssertTrue(mockCommandRunner.called(command))
    }
}
