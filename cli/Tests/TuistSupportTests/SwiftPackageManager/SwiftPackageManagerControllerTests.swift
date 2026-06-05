import Command
import Foundation
import SwifterPMCore
import Synchronization
import TSCUtility
import TuistCore
import TuistTesting
import XcodeGraph
import XCTest
@testable import TuistSupport

private final class RecordingSwifterPM: SwifterPMResolving {
    private struct State {
        var resolveRequests: [SwifterPMResolutionRequest] = []
        var updateRequests: [SwifterPMResolutionRequest] = []
    }

    private let state = Mutex(State())

    var resolveRequests: [SwifterPMResolutionRequest] {
        state.withLock { $0.resolveRequests }
    }

    var updateRequests: [SwifterPMResolutionRequest] {
        state.withLock { $0.updateRequests }
    }

    func resolveDependencies(_ request: SwifterPMResolutionRequest) async throws {
        state.withLock { $0.resolveRequests.append(request) }
    }

    func updateDependencies(_ request: SwifterPMResolutionRequest) async throws {
        state.withLock { $0.updateRequests.append(request) }
    }
}

final class SwiftPackageManagerControllerTests: TuistUnitTestCase {
    private var subject: SwiftPackageManagerController!
    private var swifterPM: RecordingSwifterPM!

    override func setUp() {
        super.setUp()

        swifterPM = RecordingSwifterPM()
        subject = SwiftPackageManagerController(
            fileSystem: fileSystem,
            commandRunner: { self.mockCommandRunner },
            swifterPM: swifterPM
        )
    }

    override func tearDown() {
        subject = nil
        swifterPM = nil

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

    func test_resolve_when_swifterpm_is_enabled() async throws {
        // Given
        let path = try temporaryPath()
        let scratchPath = try temporaryPath()
        let cachePath = try temporaryPath()
        let configPath = try temporaryPath()
        let packageInfoCachePath = try temporaryPath()
        subject = SwiftPackageManagerController(
            fileSystem: fileSystem,
            commandRunner: { self.mockCommandRunner },
            swifterPM: swifterPM,
            environmentVariables: { ["TUIST_USE_SWIFTERPM": "1"] }
        )

        // When
        try await subject.resolve(
            at: path,
            arguments: [
                "--scratch-path", scratchPath.pathString,
                "--cache-path=\(cachePath.pathString)",
                "--config-path", configPath.pathString,
                "--default-registry-url", "https://registry.tuist.dev/api/registry/swift",
                "--package-info-cache-path=\(packageInfoCachePath.pathString)",
                "--disable-sandbox",
                "--force-resolved-versions",
                "--skip-update",
                "--quiet",
                "--replace-scm-with-registry",
            ],
            printOutput: true
        )

        // Then
        XCTAssertEqual(mockCommandRunner.calls, [])
        let request = try XCTUnwrap(swifterPM.resolveRequests.first)
        XCTAssertEqual(request.packageDirectory, URL(fileURLWithPath: path.pathString).standardizedFileURL)
        XCTAssertEqual(request.scratchDirectory, URL(fileURLWithPath: scratchPath.pathString).standardizedFileURL)
        XCTAssertEqual(request.cacheDirectory, URL(fileURLWithPath: cachePath.pathString).standardizedFileURL)
        XCTAssertEqual(request.registryConfigurationPath, URL(fileURLWithPath: configPath.pathString).standardizedFileURL)
        XCTAssertEqual(request.defaultRegistryURL, "https://registry.tuist.dev/api/registry/swift")
        XCTAssertEqual(
            request.packageInfoCacheDirectory,
            URL(fileURLWithPath: packageInfoCachePath.pathString).standardizedFileURL
        )
        XCTAssertTrue(request.disableSandbox)
        XCTAssertTrue(request.forceResolvedVersions)
        XCTAssertTrue(request.skipUpdate)
        XCTAssertTrue(request.quiet)
        XCTAssertEqual(request.scmToRegistryTransformation, .replaceSCMWithRegistry)
    }

    func test_resolve_when_swifterpm_is_enabled_and_printOutput_is_false_setsQuiet() async throws {
        // Given
        let path = try temporaryPath()
        subject = SwiftPackageManagerController(
            fileSystem: fileSystem,
            commandRunner: { self.mockCommandRunner },
            swifterPM: swifterPM,
            environmentVariables: { ["TUIST_USE_SWIFTERPM": "1"] }
        )

        // When
        try await subject.resolve(
            at: path,
            arguments: [],
            printOutput: false
        )

        // Then
        let request = try XCTUnwrap(swifterPM.resolveRequests.first)
        XCTAssertTrue(request.quiet)
    }

    func test_resolve_when_swifterpm_is_enabled_and_unsupportedArgument_is_passed_fails() async throws {
        // Given
        let path = try temporaryPath()
        subject = SwiftPackageManagerController(
            fileSystem: fileSystem,
            commandRunner: { self.mockCommandRunner },
            swifterPM: swifterPM,
            environmentVariables: { ["TUIST_USE_SWIFTERPM": "1"] }
        )

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.resolve(
                at: path,
                arguments: ["--unsupported"],
                printOutput: false
            ),
            SwiftPackageManagerControllerError.unsupportedSwifterPMArguments(["--unsupported"])
        )
    }

    func test_resolve_when_swifterpm_is_enabled_and_transformArgumentsConflict_fails() async throws {
        // Given
        let path = try temporaryPath()
        subject = SwiftPackageManagerController(
            fileSystem: fileSystem,
            commandRunner: { self.mockCommandRunner },
            swifterPM: swifterPM,
            environmentVariables: { ["TUIST_USE_SWIFTERPM": "1"] }
        )

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.resolve(
                at: path,
                arguments: [
                    "--replace-scm-with-registry",
                    "--use-registry-identity-for-scm",
                ],
                printOutput: false
            ),
            SwiftPackageManagerControllerError.conflictingSCMToRegistryTransformationArguments
        )
    }

    func test_update_when_swifterpm_is_enabled() async throws {
        // Given
        let path = try temporaryPath()
        let buildPath = try temporaryPath()
        subject = SwiftPackageManagerController(
            fileSystem: fileSystem,
            commandRunner: { self.mockCommandRunner },
            swifterPM: swifterPM,
            environmentVariables: { ["TUIST_USE_SWIFTERPM": "1"] }
        )

        // When
        try await subject.update(
            at: path,
            arguments: [
                "--build-path=\(buildPath.pathString)",
                "--disable-automatic-resolution",
                "--use-registry-identity-for-scm",
            ],
            printOutput: false
        )

        // Then
        XCTAssertEqual(mockCommandRunner.calls, [])
        let request = try XCTUnwrap(swifterPM.updateRequests.first)
        XCTAssertEqual(request.packageDirectory, URL(fileURLWithPath: path.pathString).standardizedFileURL)
        XCTAssertEqual(request.scratchDirectory, URL(fileURLWithPath: buildPath.pathString).standardizedFileURL)
        XCTAssertTrue(request.forceResolvedVersions)
        XCTAssertTrue(request.quiet)
        XCTAssertEqual(request.scmToRegistryTransformation, .useRegistryIdentityForSCM)
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
