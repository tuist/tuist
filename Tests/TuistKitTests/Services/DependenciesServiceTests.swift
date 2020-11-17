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
    private var manifestLoader: MockManifestLoader!

    private var subject: DependenciesService!

    override func setUp() {
        super.setUp()

        dependenciesController = MockDependenciesController()
        manifestLoader = MockManifestLoader()

        subject = DependenciesService(dependenciesController: dependenciesController,
                                      manifestLoader: manifestLoader)
    }

    override func tearDown() {
        subject = nil

        dependenciesController = nil
        manifestLoader = nil

        super.tearDown()
    }

    // MARK: - Fetch Dependencies
    
    func test_run_fetch() throws {
        // Given
        let stubbedPath = try temporaryPath()
        manifestLoader.loadDependenciesStub = { invokedPath in
            XCTAssertEqual(invokedPath, stubbedPath)
            return .test(name: "Dependency1", requirement: .exact("1.1.1"))
        }
        
        let expectedCarthageDependencies: [CarthageDependency] = [
            .init(name: "Dependency1", requirement: .exact("1.1.1"))
        ]

        // When
        try subject.run(path: stubbedPath.pathString, method: .fetch)

        // Then
        XCTAssertTrue(dependenciesController.invokedInstall)
        XCTAssertEqual(dependenciesController.invokedInstallCount, 1)
        XCTAssertEqual(dependenciesController.invokedInstallParameters?.path, stubbedPath)
        XCTAssertEqual(dependenciesController.invokedInstallParameters?.method, .fetch)
        XCTAssertEqual(dependenciesController.invokedInstallParameters?.carthageDependencies, expectedCarthageDependencies)
    }

    func test_run_fetch_rethorws_an_error_when_dependencies_controller_throws_error() throws {
        // Given
        let stubbedPath = try temporaryPath()
        manifestLoader.loadDependenciesStub = { invokedPath in
            XCTAssertEqual(invokedPath, stubbedPath)
            return .test(name: "Dependency1", requirement: .exact("1.1.1"))
        }
        let error = TestError("Failed fetching!")
        dependenciesController.stubbedInstallError = error

        // When/Then
        XCTAssertThrowsSpecific(try subject.run(path: stubbedPath.pathString, method: .fetch), error)
    }
    
    func test_run_fetch_rethorws_an_error_when_manifest_loader_throws_error() throws {
        // Given
        let stubbedPath = try temporaryPath()
        
        let error = TestError("Failed fetching!")
        manifestLoader.loadDependenciesStub = { _ in
            throw error
        }

        // When/Then
        XCTAssertThrowsSpecific(try subject.run(path: stubbedPath.pathString, method: .fetch), error)
    }
    
    // MARK: - Update Dependencies
    
    func test_run_update() throws {
        // Given
        let stubbedPath = try temporaryPath()
        manifestLoader.loadDependenciesStub = { invokedPath in
            XCTAssertEqual(invokedPath, stubbedPath)
            return .test(name: "Dependency1", requirement: .exact("1.1.1"))
        }
        
        let expectedCarthageDependencies: [CarthageDependency] = [
            .init(name: "Dependency1", requirement: .exact("1.1.1"))
        ]

        // When
        try subject.run(path: stubbedPath.pathString, method: .update)

        // Then
        XCTAssertTrue(dependenciesController.invokedInstall)
        XCTAssertEqual(dependenciesController.invokedInstallCount, 1)
        XCTAssertEqual(dependenciesController.invokedInstallParameters?.path, stubbedPath)
        XCTAssertEqual(dependenciesController.invokedInstallParameters?.method, .update)
        XCTAssertEqual(dependenciesController.invokedInstallParameters?.carthageDependencies, expectedCarthageDependencies)
    }

    func test_run_update_thorws_an_error() throws {
        // Given
        let stubbedPath = try temporaryPath()
        manifestLoader.loadDependenciesStub = { invokedPath in
            XCTAssertEqual(invokedPath, stubbedPath)
            return .test(name: "Dependency1", requirement: .exact("1.1.1"))
        }
        let error = TestError("Failed fetching!")
        dependenciesController.stubbedInstallError = error

        // When/Then
        XCTAssertThrowsSpecific(try subject.run(path: stubbedPath.pathString, method: .update), error)
    }

    func test_run_update_rethorws_an_error_when_manifest_loader_throws_error() throws {
        // Given
        let stubbedPath = try temporaryPath()

        let error = TestError("Failed fetching!")
        manifestLoader.loadDependenciesStub = { _ in
            throw error
        }

        // When/Then
        XCTAssertThrowsSpecific(try subject.run(path: stubbedPath.pathString, method: .update), error)
    }
}
