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
            Dependencies([
                .carthage(origin: .github(path: "Dependency1"), requirement: .exact("1.1.1"), platforms: [.iOS]),
                .carthage(origin: .git(path: "Dependency1"), requirement: .exact("2.3.4"), platforms: [.macOS, .tvOS]),
            ])
        }

        // When
        let model = try subject.loadDependencies(at: stubbedPath)

        // Then
        let expectedCarthageModels: [TuistGraph.CarthageDependency] = [
            CarthageDependency(origin: .github(path: "Dependency1"), requirement: .exact("1.1.1"), platforms: Set([.iOS])),
            CarthageDependency(origin: .git(path: "Dependency1"), requirement: .exact("2.3.4"), platforms: Set([.macOS, .tvOS])),
        ]
        let expectedDependenciesModel = TuistGraph.Dependencies(carthageDependencies: expectedCarthageModels)

        XCTAssertEqual(model, expectedDependenciesModel)
    }
}
