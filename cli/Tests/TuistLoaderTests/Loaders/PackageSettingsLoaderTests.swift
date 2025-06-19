import Foundation
import Mockable
import TSCUtility
import TuistCore
import TuistRootDirectoryLocator
import TuistSupport
import XcodeGraph
import XCTest

@testable import ProjectDescription
@testable import TuistLoader
@testable import TuistTesting

final class PackageSettingsLoaderTests: TuistUnitTestCase {
    private var manifestLoader: MockManifestLoading!
    private var swiftPackageManagerController: MockSwiftPackageManagerControlling!
    private var manifestFilesLocator: MockManifestFilesLocating!
    private var rootDirectoryLocator: MockRootDirectoryLocating!
    private var subject: PackageSettingsLoader!

    override func setUpWithError() throws {
        super.setUp()

        manifestLoader = .init()
        swiftPackageManagerController = MockSwiftPackageManagerControlling()
        manifestFilesLocator = MockManifestFilesLocating()
        rootDirectoryLocator = MockRootDirectoryLocating()

        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(try temporaryPath())

        subject = PackageSettingsLoader(
            manifestLoader: manifestLoader,
            swiftPackageManagerController: swiftPackageManagerController,
            manifestFilesLocator: manifestFilesLocator,
            rootDirectoryLocator: rootDirectoryLocator
        )
    }

    override func tearDown() {
        subject = nil
        manifestLoader = nil
        swiftPackageManagerController = nil
        rootDirectoryLocator = nil

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
            .loadPackageSettings(at: .any, disableSandbox: .any)
            .willReturn(.test())

        given(swiftPackageManagerController)
            .getToolsVersion(at: .any)
            .willReturn("5.4.9")

        // When
        let got = try await subject.loadPackageSettings(at: temporaryPath, with: plugins, disableSandbox: false)

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
            targetSettings: [:]
        )
        verify(manifestLoader)
            .register(plugins: .any)
            .called(1)
        XCTAssertEqual(got, expected)
    }
}
