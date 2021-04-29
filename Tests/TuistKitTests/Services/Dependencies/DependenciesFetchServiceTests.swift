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

final class DependenciesFetchServiceTests: TuistUnitTestCase {
    private var dependenciesController: MockDependenciesController!
    private var dependenciesModelLoader: MockDependenciesModelLoader!

    private var subject: DependenciesFetchService!

    override func setUp() {
        super.setUp()

        dependenciesController = MockDependenciesController()
        dependenciesModelLoader = MockDependenciesModelLoader()

        subject = DependenciesFetchService(
            dependenciesController: dependenciesController,
            dependenciesModelLoader: dependenciesModelLoader
        )
    }

    override func tearDown() {
        subject = nil

        dependenciesController = nil
        dependenciesModelLoader = nil

        super.tearDown()
    }

    func test_run() throws {
        // Given
        let stubbedPath = try temporaryPath()
        let stubbedDependencies = Dependencies(
            carthage: .init(
                [
                    .github(path: "Dependency1", requirement: .exact("1.1.1")),
                ],
                options: []
            ),
            swiftPackageManager: .init(
                [
                    .remote(url: "Depedency1/Depedency1", requirement: .upToNextMajor("1.2.3")),
                ]
            ),
            platforms: [.iOS, .macOS]
        )
        dependenciesModelLoader.loadDependenciesStub = { _ in stubbedDependencies }
        
        dependenciesController.fetchStub = { path, dependencies in
            XCTAssertEqual(path, stubbedPath)
            XCTAssertEqual(dependencies, stubbedDependencies)
        }

        // When
        try subject.run(path: stubbedPath.pathString)

        // Then
        XCTAssertTrue(dependenciesModelLoader.invokedLoadDependencies)
        XCTAssertTrue(dependenciesController.invokedFetch)

        XCTAssertFalse(dependenciesController.invokedUpdate)
    }
}
