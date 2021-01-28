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

        subject = DependenciesFetchService(dependenciesController: dependenciesController,
                                           dependenciesModelLoader: dependenciesModelLoader)
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
            carthageDependencies: [
                CarthageDependency(origin: .github(path: "Dependency1"), requirement: .exact("1.1.1"), platforms: [.iOS, .macOS]),
            ],
            swiftPackageManagerDependencies: [
            ]
        )
        dependenciesModelLoader.loadDependenciesStub = { _ in stubbedDependencies }

        // When
        try subject.run(path: stubbedPath.pathString)

        // Then
        XCTAssertTrue(dependenciesController.invokedFetch)
        XCTAssertEqual(dependenciesController.invokedFetchCount, 1)
        XCTAssertEqual(dependenciesController.invokedFetchParameters?.path, stubbedPath)
        XCTAssertEqual(dependenciesController.invokedFetchParameters?.dependencies, stubbedDependencies)

        XCTAssertTrue(dependenciesModelLoader.invokedLoadDependencies)
        XCTAssertEqual(dependenciesModelLoader.invokedLoadDependenciesCount, 1)
        XCTAssertEqual(dependenciesModelLoader.invokedLoadDependenciesParameters, stubbedPath)
    }
}
