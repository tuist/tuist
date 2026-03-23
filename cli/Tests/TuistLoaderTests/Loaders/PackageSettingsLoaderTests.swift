import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import TSCUtility
import Testing
import TuistCore
import TuistRootDirectoryLocator
import TuistSupport
import XcodeGraph

@testable import ProjectDescription
@testable import TuistLoader
@testable import TuistTesting

struct PackageSettingsLoaderTests {
    private let manifestLoader: MockManifestLoading
    private let swiftPackageManagerController: MockSwiftPackageManagerControlling
    private let manifestFilesLocator: MockManifestFilesLocating
    private let rootDirectoryLocator: MockRootDirectoryLocating
    private let subject: PackageSettingsLoader

    init() throws {
        manifestLoader = .init()
        swiftPackageManagerController = MockSwiftPackageManagerControlling()
        manifestFilesLocator = MockManifestFilesLocating()
        rootDirectoryLocator = MockRootDirectoryLocating()

        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(temporaryPath)

        subject = PackageSettingsLoader(
            manifestLoader: manifestLoader,
            swiftPackageManagerController: swiftPackageManagerController,
            manifestFilesLocator: manifestFilesLocator,
            rootDirectoryLocator: rootDirectoryLocator
        )
    }

    @Test(.inTemporaryDirectory) func loadPackageSettings() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
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

        let got = try await subject.loadPackageSettings(at: temporaryPath, with: plugins, disableSandbox: false)

        let expected: TuistCore.PackageSettings = .init(
            productTypes: [:],
            productDestinations: [:],
            baseSettings: XcodeGraph.Settings(
                base: [:], baseDebug: [:],
                configurations: [
                    .release: XcodeGraph.Configuration(settings: [:], xcconfig: nil),
                    .debug: XcodeGraph.Configuration(settings: [:], xcconfig: nil),
                ],
                defaultSettings: .recommended
            ),
            expectedSignatures: [:],
            targetSettings: [:]
        )
        verify(manifestLoader)
            .register(plugins: .any)
            .called(1)
        #expect(got == expected)
    }
}
