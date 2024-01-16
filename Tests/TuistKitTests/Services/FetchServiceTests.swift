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
    private var manifestLoader: MockManifestLoader!
    private var dependenciesController: MockDependenciesController!
    private var packageSettingsLoader: MockPackageSettingsLoader!
    private var dependenciesModelLoader: MockDependenciesModelLoader!

    private var subject: FetchService!

    override func setUp() {
        super.setUp()

        pluginService = MockPluginService()
        configLoader = MockConfigLoader()
        manifestLoader = MockManifestLoader()
        manifestLoader.manifestsAtStub = { _ in [.project] }
        dependenciesController = MockDependenciesController()
        dependenciesModelLoader = MockDependenciesModelLoader()
        packageSettingsLoader = MockPackageSettingsLoader()

        subject = FetchService(
            pluginService: pluginService,
            configLoader: configLoader,
            manifestLoader: manifestLoader,
            dependenciesController: dependenciesController,
            dependenciesModelLoader: dependenciesModelLoader,
            packageSettingsLoader: packageSettingsLoader
        )
    }

    override func tearDown() {
        subject = nil

        pluginService = nil
        configLoader = nil
        dependenciesController = nil
        dependenciesModelLoader = nil

        super.tearDown()
    }

    func test_run_when_updating_dependencies() async throws {
        // Given
        let stubbedPath = try temporaryPath()
        let stubbedDependencies = Dependencies(
            carthage: .init(
                [
                    .git(path: "Dependency1", requirement: .exact("1.1.1")),
                ]
            ),
            swiftPackageManager: .init(
                .packages([
                    .remote(url: "Dependency1/Dependency1", requirement: .upToNextMajor("1.2.3")),
                ]),
                productTypes: [:], baseSettings: .default,
                targetSettings: [:]
            ),
            platforms: [.iOS, .macOS]
        )
        dependenciesModelLoader.loadDependenciesStub = { _, _ in stubbedDependencies }

        let stubbedSwiftVersion = TSCUtility.Version(5, 3, 0)
        configLoader.loadConfigStub = { _ in Config.test(swiftVersion: stubbedSwiftVersion) }

        dependenciesController.legacyUpdateStub = { path, dependencies, swiftVersion in
            XCTAssertEqual(path, stubbedPath)
            XCTAssertEqual(dependencies, stubbedDependencies)
            XCTAssertEqual(swiftVersion, stubbedSwiftVersion)
            return .none
        }
        dependenciesController.saveStub = { dependenciesGraph, path in
            XCTAssertEqual(dependenciesGraph, .none)
            XCTAssertEqual(path, stubbedPath)
        }
        pluginService.fetchRemotePluginsStub = { _ in
            _ = Plugins.test()
        }

        try fileHandler.touch(
            stubbedPath.appending(
                components: Constants.tuistDirectoryName, Manifest.dependencies.fileName(stubbedPath)
            )
        )

        // When
        try await subject.run(
            path: stubbedPath.pathString,
            update: true
        )

        // Then
        XCTAssertTrue(dependenciesController.invokedUpdate)
        XCTAssertTrue(dependenciesModelLoader.invokedLoadDependencies)
        XCTAssertTrue(dependenciesController.invokedSave)

        XCTAssertFalse(dependenciesController.invokedFetch)
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
        let stubbedDependencies = Dependencies(
            carthage: .init(
                [
                    .github(path: "Dependency1", requirement: .exact("1.1.1")),
                ]
            ),
            swiftPackageManager: .init(
                .packages([
                    .remote(url: "Dependency1/Dependency1", requirement: .upToNextMajor("1.2.3")),
                ]),
                productTypes: [:],
                baseSettings: .default,
                targetSettings: [:]
            ),
            platforms: [.iOS, .macOS]
        )
        dependenciesModelLoader.loadDependenciesStub = { _, _ in stubbedDependencies }

        let stubbedSwiftVersion = TSCUtility.Version(5, 3, 0)
        configLoader.loadConfigStub = { _ in Config.test(swiftVersion: stubbedSwiftVersion) }

        dependenciesController.legacyFetchStub = { path, dependencies, swiftVersion in
            XCTAssertEqual(path, stubbedPath)
            XCTAssertEqual(dependencies, stubbedDependencies)
            XCTAssertEqual(swiftVersion, stubbedSwiftVersion)
            return .none
        }
        dependenciesController.saveStub = { dependenciesGraph, path in
            XCTAssertEqual(dependenciesGraph, .none)
            XCTAssertEqual(path, stubbedPath)
        }
        pluginService.fetchRemotePluginsStub = { _ in }

        try fileHandler.touch(
            stubbedPath.appending(
                components: Constants.tuistDirectoryName, Manifest.dependencies.fileName(stubbedPath)
            )
        )

        // When
        try await subject.run(
            path: stubbedPath.pathString,
            update: false
        )

        // Then
        XCTAssertTrue(dependenciesModelLoader.invokedLoadDependencies)
        XCTAssertTrue(dependenciesController.invokedFetch)
        XCTAssertTrue(dependenciesController.invokedSave)

        XCTAssertFalse(dependenciesController.invokedUpdate)
    }

    func test_fetch_when_from_a_tuist_project_directory() async throws {
        // Given
        let exp = expectation(description: "awaiting path validation")
        let temporaryDirectory = try temporaryPath()
        let expectedFoundDependenciesLocation = temporaryDirectory.appending(
            components: Constants.tuistDirectoryName, Manifest.dependencies.fileName(temporaryDirectory)
        )
        let stubbedDependencies = Dependencies(
            carthage: nil,
            swiftPackageManager: nil,
            platforms: [.iOS, .macOS]
        )

        // When looking for the Dependencies.swift file the model loader will search in the given path
        // This is where we will assert
        dependenciesModelLoader.loadDependenciesStub = { path, _ in
            defer { exp.fulfill() }
            XCTAssertEqual(temporaryDirectory, path)
            return stubbedDependencies
        }

        // Dependencies.swift in root
        try fileHandler.touch(expectedFoundDependenciesLocation)

        // When - This will cause the `loadDependenciesStub` closure to be called and assert if needed
        try await subject.run(
            path: temporaryDirectory.pathString,
            update: false
        )
        await fulfillment(of: [exp], timeout: 0.1)
    }

    func test_fetch_path_is_found_in_tuist_project_directory_but_manifest_is_in_nested_directory() async throws {
        // Given
        let exp = expectation(description: "awaiting path validation")
        let temporaryDirectory = try temporaryPath()
        let manifestPath = temporaryDirectory
            .appending(components: ["First", "Second"])
        let expectedFoundDependenciesLocation = temporaryDirectory.appending(
            components: Constants.tuistDirectoryName, Manifest.dependencies.fileName(temporaryDirectory)
        )
        let stubbedDependencies = Dependencies(
            carthage: nil,
            swiftPackageManager: nil,
            platforms: [.iOS, .macOS]
        )

        // When looking for the Dependencies.swift file the model loader will search in the given path
        // This is where we will assert
        dependenciesModelLoader.loadDependenciesStub = { path, _ in
            defer { exp.fulfill() }
            XCTAssertEqual(temporaryDirectory, path)
            return stubbedDependencies
        }

        // Dependencies.swift in root
        try fileHandler.touch(expectedFoundDependenciesLocation)

        // When - This will cause the `loadDependenciesStub` closure to be called and assert if needed
        try await subject.run(
            path: manifestPath.pathString,
            update: false
        )
        await fulfillment(of: [exp], timeout: 0.1)
    }

    func test_fetch_path_is_found_in_nested_manifest_directory() async throws {
        // Given
        let exp = expectation(description: "awaiting path validation")
        let temporaryDirectory = try temporaryPath()
        let manifestPath = temporaryDirectory
            .appending(components: ["First", "Second"])
        let expectedFoundDependenciesLocation = manifestPath.appending(
            components: Constants.tuistDirectoryName, Manifest.dependencies.fileName(temporaryDirectory)
        )
        let stubbedDependencies = Dependencies(
            carthage: nil,
            swiftPackageManager: nil,
            platforms: [.iOS, .macOS]
        )

        // When looking for the Dependencies.swift file the model loader will search in the given path
        // This is where we will assert
        dependenciesModelLoader.loadDependenciesStub = { path, _ in
            defer { exp.fulfill() }
            XCTAssertEqual(manifestPath, path)
            return stubbedDependencies
        }

        // Dependencies.swift in root
        try fileHandler.touch(expectedFoundDependenciesLocation)

        // When - This will cause the `loadDependenciesStub` closure to be called and assert if needed
        try await subject.run(
            path: manifestPath.pathString,
            update: false
        )
        await fulfillment(of: [exp], timeout: 0.1)
    }
}
