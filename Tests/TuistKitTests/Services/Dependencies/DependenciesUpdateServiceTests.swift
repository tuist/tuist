import Foundation
import TSCBasic
import TuistCore
import XCTest

#warning("TODO: do I need this import? Replace with TuistCore?")
import ProjectDescription

@testable import TuistCoreTesting
@testable import TuistLoaderTesting
@testable import TuistDependenciesTesting
@testable import TuistKit
@testable import TuistSupportTesting

final class DependenciesUpdateServiceTests: TuistUnitTestCase {
    private var dependenciesController: MockDependenciesController!
    private var manifestLoader: MockManifestLoader!

    private var subject: DependenciesUpdateService!

    override func setUp() {
        super.setUp()

        dependenciesController = MockDependenciesController()
        manifestLoader = MockManifestLoader()

        subject = DependenciesUpdateService(dependenciesController: dependenciesController,
                                            manifestLoader: manifestLoader)
    }

    override func tearDown() {
        subject = nil

        dependenciesController = nil
        manifestLoader = nil

        super.tearDown()
    }

    func test_run() throws {
        // Given
        let stubbedPath = try temporaryPath()
        let stubbedDependencies = Dependencies.test()
        manifestLoader.loadDependenciesStub = { invokedPath in
            XCTAssertEqual(invokedPath, stubbedPath)
            return stubbedDependencies
        }

        // When
        try subject.run(path: stubbedPath.pathString)

        // Then
        XCTAssertTrue(dependenciesController.invokedInstall)
        XCTAssertEqual(dependenciesController.invokedInstallCount, 1)
        XCTAssertEqual(dependenciesController.invokedInstallParameters?.path, stubbedPath)
        XCTAssertEqual(dependenciesController.invokedInstallParameters?.method, .update)
        XCTAssertEqual(dependenciesController.invokedInstallParameters?.dependencies, stubbedDependencies.dependencies)
    }

    func test_run_thorws_an_error() throws {
        // Given
        let stubbedPath = try temporaryPath()
        let stubbedDependencies = Dependencies.test()
        manifestLoader.loadDependenciesStub = { invokedPath in
            XCTAssertEqual(invokedPath, stubbedPath)
            return stubbedDependencies
        }
        let error = TestError("Failed fetching!")
        dependenciesController.stubbedInstallError = error

        // When/Then
        XCTAssertThrowsSpecific(try subject.run(path: stubbedPath.pathString), error)
    }
    
    func test_run_rethorws_an_error_when_manifest_loader_throws_error() throws {
        // Given
        let stubbedPath = try temporaryPath()
        
        let error = TestError("Failed fetching!")
        manifestLoader.loadDependenciesStub = { _ in
            throw error
        }

        // When/Then
        XCTAssertThrowsSpecific(try subject.run(path: stubbedPath.pathString), error)
    }
}
