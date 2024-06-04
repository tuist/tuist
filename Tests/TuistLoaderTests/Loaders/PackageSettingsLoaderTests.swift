import Foundation
import MockableTest
import TSCBasic
import TSCUtility
import TuistCore
import TuistCoreTesting
import XcodeProjectGenerator
import XcodeProjectGeneratorTesting
import TuistSupport
import XCTest

@testable import ProjectDescription
@testable import TuistLoader
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class PackageSettingsLoaderTests: TuistUnitTestCase {
    private var manifestLoader: MockManifestLoader!
    private var swiftPackageManagerController: MockSwiftPackageManagerController!
    private var manifestFilesLocator: MockManifestFilesLocating!
    private var subject: PackageSettingsLoader!

    override func setUp() {
        super.setUp()

        manifestLoader = MockManifestLoader()
        swiftPackageManagerController = MockSwiftPackageManagerController()
        manifestFilesLocator = MockManifestFilesLocating()
        subject = PackageSettingsLoader(
            manifestLoader: manifestLoader,
            swiftPackageManagerController: swiftPackageManagerController,
            fileHandler: fileHandler,
            manifestFilesLocator: manifestFilesLocator
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
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(temporaryPath)

        swiftPackageManagerController.getToolsVersionStub = { _ in
            TSCUtility.Version("5.4.9")
        }

        // When
        let got = try subject.loadPackageSettings(at: temporaryPath, with: plugins)

        // Then
        let expected: XcodeProjectGenerator.PackageSettings = .init(
            productTypes: [:],
            productDestinations: [:],
            baseSettings: XcodeProjectGenerator.Settings(
                base: [:],
                baseDebug: [:],
                configurations: [
                    .release: XcodeProjectGenerator.Configuration(settings: [:], xcconfig: nil),
                    .debug: XcodeProjectGenerator.Configuration(settings: [:], xcconfig: nil),
                ],
                defaultSettings: .recommended
            ),
            targetSettings: [:],
            swiftToolsVersion: TSCUtility.Version("5.4.9")
        )
        XCTAssertEqual(manifestLoader.registerPluginsCount, 1)
        XCTAssertEqual(got, expected)
    }
}
