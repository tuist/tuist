import Foundation
import Mockable
import Path
import TSCUtility
import TuistCore
import TuistCoreTesting
import TuistLoader
import TuistPluginTesting
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistKit

final class InstallServiceTests: TuistUnitTestCase {
    private var pluginService: MockPluginService!
    private var configLoader: MockConfigLoading!
    private var swiftPackageManagerController: MockSwiftPackageManagerControlling!
    private var manifestFilesLocator: MockManifestFilesLocating!

    private var subject: InstallService!

    override func setUp() {
        super.setUp()

        pluginService = MockPluginService()
        configLoader = MockConfigLoading()
        swiftPackageManagerController = MockSwiftPackageManagerControlling()
        manifestFilesLocator = MockManifestFilesLocating()

        subject = InstallService(
            pluginService: pluginService,
            configLoader: configLoader,
            swiftPackageManagerController: swiftPackageManagerController,
            manifestFilesLocator: manifestFilesLocator
        )
    }

    override func tearDown() {
        subject = nil

        pluginService = nil
        configLoader = nil
        swiftPackageManagerController = nil
        manifestFilesLocator = nil

        super.tearDown()
    }

    func test_run_when_updating_dependencies() async throws {
        // Given
        let stubbedPath = try temporaryPath()
        let expectedPackageResolvedPath = stubbedPath.appending(components: ["Tuist", "Package.resolved"])

        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(stubbedPath.appending(components: "Tuist", "Package.swift"))
        given(swiftPackageManagerController)
            .update(at: .any, arguments: .any, printOutput: .any)
            .willReturn()

        let stubbedSwiftVersion = TSCUtility.Version(5, 3, 0)
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(
                Config.test(swiftVersion: .init(stringLiteral: stubbedSwiftVersion.description))
            )

        pluginService.fetchRemotePluginsStub = { _ in
            _ = Plugins.test()
        }

        try fileHandler.touch(
            stubbedPath.appending(
                component: Manifest.package.fileName(stubbedPath)
            )
        )

        // Package.resolved
        try fileHandler.touch(expectedPackageResolvedPath)
        try fileHandler.write("resolved", path: expectedPackageResolvedPath, atomically: true)

        // When
        try await subject.run(
            path: stubbedPath.pathString,
            update: true
        )

        let savedPackageResolvedPath = stubbedPath.appending(components: ["Tuist", ".build", "Derived", "Package.resolved"])
        let savedPackageResolvedContents = try fileHandler.readTextFile(savedPackageResolvedPath)

        // Then
        verify(swiftPackageManagerController)
            .update(at: .any, arguments: .any, printOutput: .any)
            .called(1)
        verify(swiftPackageManagerController)
            .resolve(at: .any, arguments: .any, printOutput: .any)
            .called(0)
        XCTAssertEqual(savedPackageResolvedContents, "resolved")
    }

    func test_run_when_installing_plugins() async throws {
        // Given
        let config = Config.test(
            plugins: [
                .git(url: "url", gitReference: .tag("tag"), directory: nil, releaseUrl: nil),
            ]
        )
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(config)
        var invokedConfig: Config?
        pluginService.loadPluginsStub = { config in
            invokedConfig = config
            return .test()
        }
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(nil)

        // When
        try await subject.run(
            path: nil,
            update: false
        )

        // Then
        XCTAssertEqual(invokedConfig, config)
    }

    func test_run_when_installing_dependencies() async throws {
        // Given
        let stubbedPath = try temporaryPath()
        let expectedPackageResolvedPath = stubbedPath.appending(components: ["Tuist", "Package.resolved"])

        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(stubbedPath.appending(components: "Tuist", "Package.swift"))
        given(swiftPackageManagerController)
            .resolve(at: .any, arguments: .any, printOutput: .any)
            .willReturn()

        let stubbedSwiftVersion = TSCUtility.Version(5, 3, 0)
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(
                Config.test(swiftVersion: .init(stringLiteral: stubbedSwiftVersion.description))
            )

        pluginService.fetchRemotePluginsStub = { _ in }

        try fileHandler.touch(
            stubbedPath.appending(
                component: Manifest.package.fileName(stubbedPath)
            )
        )

        // Package.resolved
        try fileHandler.touch(expectedPackageResolvedPath)
        try fileHandler.write("resolved", path: expectedPackageResolvedPath, atomically: true)

        // When
        try await subject.run(
            path: stubbedPath.pathString,
            update: false
        )

        let savedPackageResolvedPath = stubbedPath.appending(components: ["Tuist", ".build", "Derived", "Package.resolved"])
        let savedPackageResolvedContents = try fileHandler.readTextFile(savedPackageResolvedPath)

        // Then
        verify(swiftPackageManagerController)
            .update(at: .any, arguments: .any, printOutput: .any)
            .called(0)
        verify(swiftPackageManagerController)
            .resolve(at: .any, arguments: .any, printOutput: .any)
            .called(1)
        XCTAssertEqual(savedPackageResolvedContents, "resolved")
    }

    func test_install_when_from_a_tuist_project_directory() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        let expectedFoundPackageLocation = temporaryDirectory.appending(
            components: Constants.tuistDirectoryName, Manifest.package.fileName(temporaryDirectory)
        )
        let expectedPackageResolvedPath = temporaryDirectory.appending(components: ["Tuist", "Package.resolved"])

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(expectedFoundPackageLocation)
        given(swiftPackageManagerController)
            .resolve(at: .any, arguments: .any, printOutput: .any)
            .willReturn()

        // Dependencies.swift in root
        try fileHandler.touch(expectedFoundPackageLocation)

        // Package.resolved
        try fileHandler.touch(expectedPackageResolvedPath)
        try fileHandler.write("resolved", path: expectedPackageResolvedPath, atomically: true)

        // When - This will cause the `loadDependenciesStub` closure to be called and assert if needed
        try await subject.run(
            path: temporaryDirectory.pathString,
            update: false
        )

        let savedPackageResolvedPath = temporaryDirectory.appending(components: [
            "Tuist",
            ".build",
            "Derived",
            "Package.resolved",
        ])
        let savedPackageResolvedContents = try fileHandler.readTextFile(savedPackageResolvedPath)

        // Then
        XCTAssertEqual(savedPackageResolvedContents, "resolved")
    }

    func test_resolve_with_spm_arguments_from_config() async throws {
        // Given
        let stubbedPath = try temporaryPath()

        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(stubbedPath.appending(components: "Tuist", "Package.swift"))

        let stubbedSwiftVersion = TSCUtility.Version(5, 3, 0)
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(
                Config.test(
                    swiftVersion: .init(stringLiteral: stubbedSwiftVersion.description),
                    installOptions: .test(
                        passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"]
                    )
                )
            )

        pluginService.fetchRemotePluginsStub = { _ in
            _ = Plugins.test()
        }

        try fileHandler.touch(
            stubbedPath.appending(
                component: Manifest.package.fileName(stubbedPath)
            )
        )

        given(swiftPackageManagerController)
            .resolve(at: .any, arguments: .any, printOutput: .any)
            .willReturn()

        // When
        try await subject.run(
            path: stubbedPath.pathString,
            update: false
        )

        // Then
        verify(swiftPackageManagerController)
            .resolve(at: .any, arguments: .any, printOutput: .any)
            .called(1)
        verify(swiftPackageManagerController)
            .resolve(at: .any, arguments: .value(["--replace-scm-with-registry"]), printOutput: .any)
            .called(1)
    }

    func test_update_with_spm_arguments_from_config() async throws {
        // Given
        let stubbedPath = try temporaryPath()

        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(stubbedPath.appending(components: "Tuist", "Package.swift"))

        let stubbedSwiftVersion = TSCUtility.Version(5, 3, 0)
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(
                Config.test(
                    swiftVersion: .init(stringLiteral: stubbedSwiftVersion.description),
                    installOptions: .test(
                        passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"]
                    )
                )
            )

        pluginService.fetchRemotePluginsStub = { _ in
            _ = Plugins.test()
        }

        try fileHandler.touch(
            stubbedPath.appending(
                component: Manifest.package.fileName(stubbedPath)
            )
        )

        given(swiftPackageManagerController)
            .update(at: .any, arguments: .any, printOutput: .any)
            .willReturn()

        // When
        try await subject.run(
            path: stubbedPath.pathString,
            update: true
        )

        // Then
        verify(swiftPackageManagerController)
            .update(at: .any, arguments: .value(["--replace-scm-with-registry"]), printOutput: .any)
            .called(1)
        verify(swiftPackageManagerController)
            .resolve(at: .any, arguments: .any, printOutput: .any)
            .called(0)
    }
}
