import Foundation
import TSCBasic
import TSCUtility
import TuistCore
import TuistCoreTesting
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
    private var swiftPackageManagerController: MockSwiftPackageManagerController!
    private var manifestFilesLocator: MockManifestFilesLocator!
    private var subject: PackageSettingsLoader!

    override func setUp() {
        super.setUp()

        manifestLoader = MockManifestLoader()
        swiftPackageManagerController = MockSwiftPackageManagerController()
        manifestFilesLocator = MockManifestFilesLocator()
        subject = PackageSettingsLoader(
            manifestLoader: manifestLoader,
            swiftPackageManagerController: swiftPackageManagerController,
            fileHandler: fileHandler,
            manifestFilesLocator: MockManifestFilesLocator()
        )
    }

    override func tearDown() {
        subject = nil
        manifestLoader = nil
        swiftPackageManagerController = nil

        super.tearDown()
    }

    func test_loadPackageSettings() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let plugins = Plugins.test()

        swiftPackageManagerController.getToolsVersionStub = { _ in
            TSCUtility.Version("5.4.9")
        }

        manifestLoader.loadPackageSettingsStub = { _ in
            PackageSettings(
                platforms: [.iOS, .macOS]
            )
        }

        // When
        let got = try subject.loadPackageSettings(at: temporaryPath, with: plugins)

        // Then
        let expected: TuistGraph.PackageSettings = .init(
            productTypes: [:],
            baseSettings: TuistGraph.Settings(
                base: [:],
                baseDebug: [:],
                configurations: [
                    .release: TuistGraph.Configuration(settings: [:], xcconfig: nil),
                    .debug: TuistGraph.Configuration(settings: [:], xcconfig: nil),
                ],
                defaultSettings: .recommended
            ),
            targetSettings: [:],
            swiftToolsVersion: TSCUtility.Version("5.4.9"),
            platforms: [.iOS, .macOS]
        )
        XCTAssertEqual(manifestLoader.registerPluginsCount, 1)
        XCTAssertEqual(got, expected)
    }
}
