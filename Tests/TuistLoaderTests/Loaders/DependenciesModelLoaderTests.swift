import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest

@testable import ProjectDescription
@testable import TuistLoader
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class DependenciesModelLoaderTests: TuistUnitTestCase {
    private var manifestLoader: MockManifestLoader!

    private var subject: DependenciesModelLoader!

    override func setUp() {
        super.setUp()

        manifestLoader = MockManifestLoader()
        subject = DependenciesModelLoader(manifestLoader: manifestLoader)
    }

    override func tearDown() {
        subject = nil
        manifestLoader = nil

        super.tearDown()
    }

    func test_loadDependencies() throws {
        // Given
        let stubbedPath = try temporaryPath()
        manifestLoader.loadDependenciesStub = { _ in
            Dependencies(
                carthageDependencies: .init(
                    dependencies: [
                        .github(path: "Dependency1", requirement: .exact("1.1.1")),
                        .git(path: "Dependency1", requirement: .exact("2.3.4")),
                    ],
                    options: .init(platforms: [.iOS, .macOS], useXCFrameworks: true)
                )
            )
        }

        // When
        let model = try subject.loadDependencies(at: stubbedPath)

        // Then
        let expected: TuistGraph.Dependencies = .init(
            carthageDependencies: .init(
                dependencies: [
                    .github(path: "Dependency1", requirement: .exact("1.1.1")),
                    .git(path: "Dependency1", requirement: .exact("2.3.4")),
                ],
                options: .init(platforms: [.iOS, .macOS], useXCFrameworks: true)
            )
        )
        XCTAssertEqual(model, expected)
    }
}
