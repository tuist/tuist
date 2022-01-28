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
        let temporaryPath = try temporaryPath()
        let localSwiftPackagePath = temporaryPath.appending(component: "LocalPackage")
        let plugins = Plugins.test()

        manifestLoader.loadDependenciesStub = { _ in
            Dependencies(
                carthage: [
                    .github(path: "Dependency1", requirement: .exact("1.1.1")),
                    .git(path: "Dependency1", requirement: .exact("2.3.4")),
                ],
                swiftPackageManager: .init(
                    [
                        .local(path: Path(localSwiftPackagePath.pathString)),
                        .remote(url: "RemoteUrl.com", requirement: .exact("1.2.3")),
                    ]
                ),
                platforms: [.iOS, .macOS]
            )
        }

        // When
        let got = try subject.loadDependencies(at: temporaryPath, with: plugins)

        // Then
        let expected: TuistGraph.Dependencies = .init(
            carthage: .init(
                [
                    .github(path: "Dependency1", requirement: .exact("1.1.1")),
                    .git(path: "Dependency1", requirement: .exact("2.3.4")),
                ]
            ),
            swiftPackageManager: .init(
                [
                    .local(path: localSwiftPackagePath),
                    .remote(url: "RemoteUrl.com", requirement: .exact("1.2.3")),
                ],
                productTypes: [:],
                baseSettings: .init(configurations: [
                    .debug: .init(settings: [:], xcconfig: nil),
                    .release: .init(settings: [:], xcconfig: nil),
                ]),
                targetSettings: [:]
            ),
            platforms: [.iOS, .macOS]
        )
        XCTAssertEqual(manifestLoader.registerPluginsCount, 1)
        XCTAssertEqual(got, expected)
    }
}
