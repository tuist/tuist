import Foundation
import TSCBasic
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistLoaderTesting
@testable import TuistDependenciesTesting
@testable import TuistKit
@testable import TuistSupportTesting

final class DependenciesServiceTests: TuistUnitTestCase {
    private var dependenciesController: MockDependenciesController!
    private var dependenciesModelLoader: MockDependenciesModelLoader!

    private var subject: DependenciesService!

    override func setUp() {
        super.setUp()

        dependenciesController = MockDependenciesController()
        dependenciesModelLoader = MockDependenciesModelLoader()

        subject = DependenciesService(dependenciesController: dependenciesController,
                                      dependenciesModelLoader: dependenciesModelLoader)
    }

    override func tearDown() {
        subject = nil

        dependenciesController = nil
        dependenciesModelLoader = nil

        super.tearDown()
    }
    
    func test_run_fetch() throws {
        // Given
        let stubbedPath = try temporaryPath()
        let stubbedDependencies = Dependencies(
            carthageDependencies: [
                CarthageDependency(name: "Dependency1", requirement: .exact("1.1.1"), platforms: [.iOS, .macOS])
            ]
        )
        dependenciesModelLoader.loadDependenciesStub = { _ in stubbedDependencies }

        // When
        try subject.run(path: stubbedPath.pathString, method: .fetch)

        // Then
        XCTAssertTrue(dependenciesController.invokedInstall)
        XCTAssertEqual(dependenciesController.invokedInstallCount, 1)
        XCTAssertEqual(dependenciesController.invokedInstallParameters?.path, stubbedPath)
        XCTAssertEqual(dependenciesController.invokedInstallParameters?.method, .fetch)
        XCTAssertEqual(dependenciesController.invokedInstallParameters?.dependencies, stubbedDependencies)
        
        XCTAssertTrue(dependenciesModelLoader.invokedLoadDependencies)
        XCTAssertEqual(dependenciesModelLoader.invokedLoadDependenciesCount, 1)
        XCTAssertEqual(dependenciesModelLoader.invokedLoadDependenciesParameters, stubbedPath)
    }
    
    func test_run_update() throws {
        // Given
        let stubbedPath = try temporaryPath()
        let stubbedDependencies = Dependencies(
            carthageDependencies: [
                CarthageDependency(name: "Dependency1", requirement: .exact("1.1.1"), platforms: [.iOS, .macOS])
            ]
        )
        dependenciesModelLoader.loadDependenciesStub = { _ in stubbedDependencies }
        // When
        try subject.run(path: stubbedPath.pathString, method: .update)

        // Then
        XCTAssertTrue(dependenciesController.invokedInstall)
        XCTAssertEqual(dependenciesController.invokedInstallCount, 1)
        XCTAssertEqual(dependenciesController.invokedInstallParameters?.path, stubbedPath)
        XCTAssertEqual(dependenciesController.invokedInstallParameters?.method, .update)
        XCTAssertEqual(dependenciesController.invokedInstallParameters?.dependencies, stubbedDependencies)
        
        XCTAssertTrue(dependenciesModelLoader.invokedLoadDependencies)
        XCTAssertEqual(dependenciesModelLoader.invokedLoadDependenciesCount, 1)
        XCTAssertEqual(dependenciesModelLoader.invokedLoadDependenciesParameters, stubbedPath)
    }
}
