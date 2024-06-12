import Foundation
import MockableTest
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
    private var swiftPackageManagerController: MockSwiftPackageManagerController!
    private var manifestFilesLocator: MockManifestFilesLocating!

    private var subject: InstallService!

    override func setUp() {
        super.setUp()

        pluginService = MockPluginService()
        configLoader = MockConfigLoading()
        swiftPackageManagerController = MockSwiftPackageManagerController()
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

        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(stubbedPath.appending(components: "Tuist", "Package.swift"))

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

        // When
        try await subject.run(
            path: stubbedPath.pathString,
            update: true
        )

        // Then
        XCTAssertTrue(swiftPackageManagerController.invokedUpdate)
        XCTAssertFalse(swiftPackageManagerController.invokedResolve)
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

        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(stubbedPath.appending(components: "Tuist", "Package.swift"))

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

        // When
        try await subject.run(
            path: stubbedPath.pathString,
            update: false
        )

        // Then
        XCTAssertTrue(swiftPackageManagerController.invokedResolve)
        XCTAssertFalse(swiftPackageManagerController.invokedUpdate)
    }

    func test_install_when_from_a_tuist_project_directory() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        let expectedFoundPackageLocation = temporaryDirectory.appending(
            components: Constants.tuistDirectoryName, Manifest.package.fileName(temporaryDirectory)
        )
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(expectedFoundPackageLocation)

        // Dependencies.swift in root
        try fileHandler.touch(expectedFoundPackageLocation)

        // When - This will cause the `loadDependenciesStub` closure to be called and assert if needed
        try await subject.run(
            path: temporaryDirectory.pathString,
            update: false
        )
    }
}
