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

final class PackageSettingsLoaderTests: TuistUnitTestCase {
    private var manifestLoader: MockManifestLoader!
    private var subject: PackageSettingsLoader!

    override func setUp() {
        super.setUp()

        manifestLoader = MockManifestLoader()
        subject = PackageSettingsLoader(manifestLoader: manifestLoader)
    }

    override func tearDown() {
        subject = nil
        manifestLoader = nil

        super.tearDown()
    }

    func test_loadDependencies() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let plugins = Plugins.test()

        manifestLoader.loadPackageSettingsStub = { _ in
            PackageSettings(
                platforms: [.iOS, .macOS]
            )
        }
        manifestLoader.loadDependenciesStub = { _ in
            Dependencies(
                carthage: [
                    .github(path: "Dependency1", requirement: .exact("1.1.1")),
                    .git(path: "Dependency1", requirement: .exact("2.3.4")),
                ],
                swiftPackageManager: .init(),
                platforms: [.iOS, .macOS]
            )
        }

        // When
        let got = try subject.loadPackageSettings(at: temporaryPath, with: plugins)

        // Then
        let expected: TuistGraph.PackageSettings = .init(
            productTypes: [:],
            baseSettings: .init(configurations: [
                .debug: .init(settings: [:], xcconfig: nil),
                .release: .init(settings: [:], xcconfig: nil),
            ]),
            targetSettings: [:],
            platforms: [.iOS, .macOS]
        )
        XCTAssertEqual(manifestLoader.registerPluginsCount, 1)
        XCTAssertEqual(got, expected)
    }
}
