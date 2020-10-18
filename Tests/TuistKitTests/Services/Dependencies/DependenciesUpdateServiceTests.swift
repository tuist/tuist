import Foundation
import TSCBasic
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistDependenciesTesting
@testable import TuistKit
@testable import TuistSupportTesting

final class DependenciesUpdateServiceTests: TuistUnitTestCase {
    private var dependenciesController: MockDependenciesController!

    private var subject: DependenciesUpdateService!

    override func setUp() {
        super.setUp()

        dependenciesController = MockDependenciesController()

        subject = DependenciesUpdateService(dependenciesController: dependenciesController)
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
        XCTAssertTrue(dependenciesController.invokedInstall)
        XCTAssertEqual(dependenciesController.invokedInstallCount, 1)
        XCTAssertEqual(dependenciesController.invokedInstallParameters?.path, path)
        XCTAssertEqual(dependenciesController.invokedInstallParameters?.method, .update)
    }

    func test_run_thorws_an_error() throws {
        // Given
        let path = try temporaryPath()
        let error = TestError("Failed fetching!")
        dependenciesController.stubbedInstallError = error

        // When/Then
        XCTAssertThrowsSpecific(try subject.run(path: path.pathString), error)
    }
}
