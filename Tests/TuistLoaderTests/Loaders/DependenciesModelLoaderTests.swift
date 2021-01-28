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
            Dependencies([
                .carthage(origin: .github(path: "Dependency1"), requirement: .exact("1.1.1"), platforms: [.iOS]),
                .carthage(origin: .git(path: "Dependency1"), requirement: .exact("2.3.4"), platforms: [.macOS, .tvOS]),
                .swiftPackageManager(package: .local(path: Path(localSwiftPackagePath.pathString))),
                .swiftPackageManager(package: .remote(url: "RemoteUrl.com", requirement: .exact("1.2.3")))
            ])
        }

        // When
        let got = try subject.loadDependencies(at: temporaryPath)

        // Then
        let expected = TuistGraph.Dependencies(
            carthageDependencies: [
                CarthageDependency(origin: .github(path: "Dependency1"), requirement: .exact("1.1.1"), platforms: Set([.iOS])),
                CarthageDependency(origin: .git(path: "Dependency1"), requirement: .exact("2.3.4"), platforms: Set([.macOS, .tvOS])),
            ],
            swiftPackageManagerDependencies: [
                SwiftPackageManagerDependency(package: .local(path: localSwiftPackagePath)),
                SwiftPackageManagerDependency(package: .remote(url: "RemoteUrl.com", requirement: .exact("1.2.3")))
            ]
        )
        XCTAssertEqual(got, expected)
    }
}
