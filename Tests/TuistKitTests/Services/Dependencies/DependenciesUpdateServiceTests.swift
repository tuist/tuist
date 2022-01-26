import Foundation
import TSCBasic
import TSCUtility
import TuistCore
import TuistDependencies
import TuistGraph
import TuistGraphTesting
import XCTest

@testable import TuistCoreTesting
@testable import TuistDependenciesTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class DependenciesUpdateServiceTests: TuistUnitTestCase {
    private var dependenciesController: MockDependenciesController!
    private var configLoader: MockConfigLoader!
    private var dependenciesService: MockDependenciesService!

    private var subject: DependenciesUpdateService!

    override func setUp() {
        super.setUp()

        dependenciesController = MockDependenciesController()
        dependenciesService = MockDependenciesService()
        configLoader = MockConfigLoader()

        subject = DependenciesUpdateService(
            dependenciesController: dependenciesController,
            dependenciesService: dependenciesService,
            configLoading: configLoader
        )
    }

    override func tearDown() {
        subject = nil

        configLoader = nil
        dependenciesService = nil

        super.tearDown()
    }

    func test_run() throws {
        // Given
        let stubbedPath = try temporaryPath()
        let stubbedDependencies = Dependencies(
            carthage: .init(
                [
                    .git(path: "Dependency1", requirement: .exact("1.1.1")),
                ]
            ),
            swiftPackageManager: .init(
                [
                    .remote(url: "Dependency1/Dependency1", requirement: .upToNextMajor("1.2.3")),
                ],
                productTypes: [:],
                baseSettings: .default,
                targetSettings: [:]
            ),
            platforms: [.iOS, .macOS]
        )

        dependenciesService.loadDependenciesStub = { _, _ in stubbedDependencies }

        let stubbedSwiftVersion = TSCUtility.Version(5, 3, 0)
        configLoader.loadConfigStub = { _ in Config.test(swiftVersion: stubbedSwiftVersion) }

        dependenciesController.updateStub = { path, dependencies, swiftVersion in
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
        try subject.run(path: stubbedPath.pathString)

        // Then
        XCTAssertTrue(dependenciesController.invokedUpdate)
        XCTAssertTrue(dependenciesService.invokedLoadDependencies)
        XCTAssertTrue(dependenciesController.invokedSave)

        XCTAssertFalse(dependenciesController.invokedFetch)
    }
}
