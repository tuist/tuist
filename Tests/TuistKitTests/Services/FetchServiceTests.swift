import Foundation
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistCoreTesting
import TuistDependenciesTesting
import TuistLoaderTesting
import TuistSupportTesting
import TuistPluginTesting
import XCTest

@testable import TuistKit

final class FetchServiceTests: TuistUnitTestCase {
    private var pluginService: MockPluginService!
    private var configLoader: MockConfigLoader!
    private var dependenciesController: MockDependenciesController!
    private var dependenciesModelLoader: MockDependenciesModelLoader!

    private var subject: FetchService!

    override func setUp() {
        super.setUp()

        pluginService = MockPluginService()
        configLoader = MockConfigLoader()
        dependenciesController = MockDependenciesController()
        dependenciesModelLoader = MockDependenciesModelLoader()

        subject = FetchService(
            pluginService: pluginService,
            configLoader: configLoader,
            dependenciesController: dependenciesController,
            dependenciesModelLoader: dependenciesModelLoader
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
    
    func test_run_when_fetching_plugins() throws {
        // Given
        let config = Config.test(
            plugins: [
                .git(url: "url", gitReference: .tag("tag"))
            ]
        )
        configLoader.loadConfigStub = { _ in
            config
        }
        var invokedConfig: Config?
        pluginService.fetchRemotePluginsStub = { config in
            invokedConfig = config
        }
        
        // When
        try subject.run(path: nil, fetchCategories: [.plugins])
        
        // Then
        XCTAssertEqual(
            config, invokedConfig
        )
    }

    func test_run_when_fetching_dependencies() throws {
        // Given
        let stubbedPath = try temporaryPath()
        let stubbedDependencies = Dependencies(
            carthage: .init(
                [
                    .github(path: "Dependency1", requirement: .exact("1.1.1")),
                ]
            ),
            swiftPackageManager: .init(
                [
                    .remote(url: "Dependency1/Dependency1", requirement: .upToNextMajor("1.2.3")),
                ],
                productTypes: [:],
                deploymentTargets: [
                    .iOS("13.0", [.iphone]),
                    .macOS("10.0"),
                ]
            ),
            platforms: [.iOS, .macOS]
        )
        dependenciesModelLoader.loadDependenciesStub = { _ in stubbedDependencies }

        let stubbedSwiftVersion = TSCUtility.Version(5, 3, 0)
        configLoader.loadConfigStub = { _ in Config.test(swiftVersion: stubbedSwiftVersion) }

        dependenciesController.fetchStub = { path, dependencies, swiftVersion in
            XCTAssertEqual(path, stubbedPath)
            XCTAssertEqual(dependencies, stubbedDependencies)
            XCTAssertEqual(swiftVersion, stubbedSwiftVersion)
            return .none
        }
        dependenciesController.saveStub = { dependenciesGraph, path in
            XCTAssertEqual(dependenciesGraph, .none)
            XCTAssertEqual(path, stubbedPath)
        }

        // When
        try subject.run(path: stubbedPath.pathString, fetchCategories: [.dependencies])

        // Then
        XCTAssertTrue(dependenciesModelLoader.invokedLoadDependencies)
        XCTAssertTrue(dependenciesController.invokedFetch)
        XCTAssertTrue(dependenciesController.invokedSave)

        XCTAssertFalse(dependenciesController.invokedUpdate)
    }
}
