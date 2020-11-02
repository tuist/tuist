import Foundation
import TSCBasic
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistDependenciesTesting
@testable import TuistKit
@testable import TuistSupportTesting

final class DependenciesFetchServiceTests: TuistUnitTestCase {
    private var dependenciesController: MockDependenciesController!

    private var subject: DependenciesFetchService!

    override func setUp() {
        super.setUp()

        dependenciesController = MockDependenciesController()

        subject = DependenciesFetchService(dependenciesController: dependenciesController)
    }

    override func tearDown() {
        subject = nil

        dependenciesController = nil

        super.tearDown()
    }

    func test_run() throws {
        // Given
        let path = try temporaryPath()

        // When
        try subject.run(path: path.pathString)

        // Then
        XCTAssertTrue(dependenciesController.invokedFetch)
        XCTAssertEqual(dependenciesController.invokedFetchCount, 1)
        XCTAssertEqual(dependenciesController.invokedFetchParameters, path)

        XCTAssertFalse(dependenciesController.invokedUpdate)
    }

    func test_run_thorws_an_error() throws {
        // Given
        let path = try temporaryPath()
        let error = TestError("Failed fetching!")
        dependenciesController.stubbedFetchError = error

        // When/Then
        XCTAssertThrowsSpecific(try subject.run(path: path.pathString), error)
    }
}
