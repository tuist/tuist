import Foundation
import TSCBasic
import TSCUtility
import TuistCore
import TuistCoreTesting
import TuistDependenciesTesting
import TuistGraph
import TuistGraphTesting
import TuistLoader
import TuistLoaderTesting
import TuistPluginTesting
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistKit

final class FetchServiceTests: TuistUnitTestCase {
    private var pluginService: MockPluginService!
    private var configLoader: MockConfigLoader!
    private var swiftPackageManagerController: MockSwiftPackageManagerController!

    private var subject: FetchService!

    override func setUp() {
        super.setUp()

        pluginService = MockPluginService()
        configLoader = MockConfigLoader()
        swiftPackageManagerController = MockSwiftPackageManagerController()

        subject = FetchService(
            pluginService: pluginService,
            configLoader: configLoader,
            swiftPackageManagerController: swiftPackageManagerController
        )
    }

    override func tearDown() {
        subject = nil

        pluginService = nil
        configLoader = nil
        swiftPackageManagerController = nil

        super.tearDown()
    }

    func test_run_when_updating_dependencies() async throws {
        // Given
        let stubbedPath = try temporaryPath()

        let stubbedSwiftVersion = TSCUtility.Version(5, 3, 0)
        configLoader.loadConfigStub = { _ in Config.test(swiftVersion: stubbedSwiftVersion) }

        pluginService.fetchRemotePluginsStub = { _ in
            _ = Plugins.test()
        }

        try fileHandler.touch(
            stubbedPath.appending(
                components: Constants.tuistDirectoryName, Manifest.package.fileName(stubbedPath)
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

    func test_run_when_fetching_plugins() async throws {
        // Given
        let config = Config.test(
            plugins: [
                .git(url: "url", gitReference: .tag("tag"), directory: nil, releaseUrl: nil),
            ]
        )
        configLoader.loadConfigStub = { _ in
            config
        }
        var invokedConfig: Config?
        pluginService.loadPluginsStub = { config in
            invokedConfig = config
            return .test()
        }

        // When
        try await subject.run(
            path: nil,
            update: false
        )

        // Then
        XCTAssertEqual(invokedConfig, config)
    }

    func test_run_when_fetching_dependencies() async throws {
        // Given
        let stubbedPath = try temporaryPath()

        let stubbedSwiftVersion = TSCUtility.Version(5, 3, 0)
        configLoader.loadConfigStub = { _ in Config.test(swiftVersion: stubbedSwiftVersion) }

        pluginService.fetchRemotePluginsStub = { _ in }

        try fileHandler.touch(
            stubbedPath.appending(
                components: Constants.tuistDirectoryName, Manifest.package.fileName(stubbedPath)
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

    func test_fetch_when_from_a_tuist_project_directory() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        let expectedFoundPackageLocation = temporaryDirectory.appending(
            components: Constants.tuistDirectoryName, Manifest.package.fileName(temporaryDirectory)
        )

        // Dependencies.swift in root
        try fileHandler.touch(expectedFoundPackageLocation)

        // When - This will cause the `loadDependenciesStub` closure to be called and assert if needed
        try await subject.run(
            path: temporaryDirectory.pathString,
            update: false
        )
    }
}
