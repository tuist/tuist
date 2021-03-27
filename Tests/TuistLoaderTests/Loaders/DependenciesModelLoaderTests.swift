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
        let temporaryPath = try self.temporaryPath()
        let localSwiftPackagePath = temporaryPath.appending(component: "LocalPackage")

        manifestLoader.loadDependenciesStub = { _ in
            Dependencies(
                carthage: .carthage(
                    [
                        .github(path: "Dependency1", requirement: .exact("1.1.1")),
                        .git(path: "Dependency1", requirement: .exact("2.3.4")),
                    ],
                    options: [.useXCFrameworks, .noUseBinaries]
                ),
                swiftPackageManager: .swiftPackageManager(
                    [
                        .local(path: Path(localSwiftPackagePath.pathString)),
                        .remote(url: "RemoteUrl.com", requirement: .exact("1.2.3")),
                    ]
                ),
                platforms: [.iOS, .macOS]
            )
        }

        // When
        let got = try subject.loadDependencies(at: temporaryPath)

        // Then
        let expected: TuistGraph.Dependencies = .init(
            carthage: .init(
                [
                    .github(path: "Dependency1", requirement: .exact("1.1.1")),
                    .git(path: "Dependency1", requirement: .exact("2.3.4")),
                ],
                options: [.useXCFrameworks, .noUseBinaries]
            ),
            swiftPackageManager: .init(
                [
                    .local(path: localSwiftPackagePath),
                    .remote(url: "RemoteUrl.com", requirement: .exact("1.2.3")),
                ]
            ),
            platforms: [.iOS, .macOS]
        )
        XCTAssertEqual(got, expected)
    }
}
