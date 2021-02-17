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

    private var subject: DependenciesUpdateService!

    override func setUp() {
        super.setUp()

        dependenciesController = MockDependenciesController()
        dependenciesModelLoader = MockDependenciesModelLoader()

        subject = DependenciesUpdateService(dependenciesController: dependenciesController,
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
            carthageDependencies: .init(
                dependencies: [
                    .git(path: "Dependency1", requirement: .exact("1.1.1")),
                ],
                options: .init(platforms: [.iOS, .macOS], useXCFrameworks: false)
            )
        )
        dependenciesModelLoader.loadDependenciesStub = { _ in stubbedDependencies }

        // When/Then
        XCTAssertThrowsSpecific(try subject.run(path: stubbedPath.pathString), DependenciesUpdateServiceError.unimplemented)
    }
}
