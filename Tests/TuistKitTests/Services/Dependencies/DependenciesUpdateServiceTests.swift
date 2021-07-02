import Foundation
import TSCBasic
import TuistCore
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
    private var dependenciesModelLoader: MockDependenciesModelLoader!
    private var configLoader: MockConfigLoader!

    private var subject: DependenciesUpdateService!

    override func setUp() {
        super.setUp()

        dependenciesController = MockDependenciesController()
        dependenciesModelLoader = MockDependenciesModelLoader()
        configLoader = MockConfigLoader()

        subject = DependenciesUpdateService(
            dependenciesController: dependenciesController,
            dependenciesModelLoader: dependenciesModelLoader,
            configLoading: configLoader
        )
    }

    override func tearDown() {
        subject = nil

        dependenciesController = nil
        dependenciesModelLoader = nil
        configLoader = nil

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
                deploymentTargets: [
                    .iOS("13.0", [.iphone]),
                    .macOS("10.0"),
                ]
            ),
            platforms: [.iOS, .macOS]
        )
        dependenciesModelLoader.loadDependenciesStub = { _ in stubbedDependencies }

        let stubbedSwiftVersion = "5.3.0"
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
        XCTAssertTrue(dependenciesModelLoader.invokedLoadDependencies)
        XCTAssertTrue(dependenciesController.invokedSave)

        XCTAssertFalse(dependenciesController.invokedFetch)
    }
}
