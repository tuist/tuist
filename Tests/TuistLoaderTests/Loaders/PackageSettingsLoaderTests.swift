import Foundation
import MockableTest
import Path
import TSCUtility
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeGraph
import XCTest

@testable import ProjectDescription
@testable import TuistLoader
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class PackageSettingsLoaderTests: TuistUnitTestCase {
    private var manifestLoader: MockManifestLoading!
    private var swiftPackageManagerController: MockSwiftPackageManagerController!
    private var manifestFilesLocator: MockManifestFilesLocating!
    private var subject: PackageSettingsLoader!

    override func setUp() {
        super.setUp()

        manifestLoader = .init()
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

    func test_loadPackageSettings() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let plugins = Plugins.test()
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(temporaryPath)

        given(manifestLoader)
            .register(plugins: .any)
            .willReturn(())

        given(manifestLoader)
            .loadPackageSettings(at: .any)
            .willReturn(.test())

        swiftPackageManagerController.getToolsVersionStub = { _ in
            TSCUtility.Version("5.4.9")
        }

        // When
        let got = try await subject.loadPackageSettings(at: temporaryPath, with: plugins)

        // Then
        let expected: TuistCore.PackageSettings = .init(
            productTypes: [:],
            productDestinations: [:],
            baseSettings: XcodeGraph.Settings(
                base: [:],
                baseDebug: [:],
                configurations: [
                    .release: XcodeGraph.Configuration(settings: [:], xcconfig: nil),
                    .debug: XcodeGraph.Configuration(settings: [:], xcconfig: nil),
                ],
                defaultSettings: .recommended
            ),
            targetSettings: [:],
            swiftToolsVersion: Version(stringLiteral: "5.4.9")
        )
        verify(manifestLoader)
            .register(plugins: .any)
            .called(1)
        XCTAssertEqual(got, expected)
    }
}
