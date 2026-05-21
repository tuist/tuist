import FileSystem
import Mockable
import TuistConfig
import TuistConfigLoader
import TuistConstants
import TuistEnvironmentTesting
import TuistLoader
import TuistTesting
import XCTest

@testable import TuistKit

final class OutdatedDependenciesCheckerTests: TuistUnitTestCase {
    private var manifestFilesLocator: MockManifestFilesLocating!
    private var configLoader: MockConfigLoading!
    private var subject: OutdatedDependenciesChecker!

    override func setUp() {
        super.setUp()

        manifestFilesLocator = MockManifestFilesLocating()
        configLoader = MockConfigLoading()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(
                .test(project: .generated(.test()))
            )
        subject = OutdatedDependenciesChecker(
            manifestFilesLocator: manifestFilesLocator,
            fileSystem: FileSystem(),
            configLoader: configLoader
        )
    }

    override func tearDown() {
        subject = nil
        manifestFilesLocator = nil
        configLoader = nil

        super.tearDown()
    }

    func test_packageDependenciesAreOutdated_whenPackageResolvedMatchesDefaultScratchDirectory() async throws {
        try await withMockedEnvironment {
            // Given
            let projectDirectory = try temporaryPath()
            let packagePath = projectDirectory.appending(
                components: Constants.tuistDirectoryName,
                Constants.SwiftPackageManager.packageSwiftName
            )
            let packageDirectory = packagePath.parentDirectory
            given(manifestFilesLocator)
                .locatePackageManifest(at: .any)
                .willReturn(packagePath)

            let currentPackageResolvedPath = packageDirectory.appending(
                component: Constants.SwiftPackageManager.packageResolvedName
            )
            let savedPackageResolvedPath = packageDirectory.appending(components: [
                Constants.SwiftPackageManager.packageBuildDirectoryName,
                Constants.DerivedDirectory.name,
                Constants.SwiftPackageManager.packageResolvedName,
            ])
            try await fileSystem.makeDirectory(at: currentPackageResolvedPath.parentDirectory)
            try await fileSystem.writeText("resolved", at: currentPackageResolvedPath)
            try await fileSystem.makeDirectory(at: savedPackageResolvedPath.parentDirectory)
            try await fileSystem.writeText("resolved", at: savedPackageResolvedPath)

            // When
            let got = try await subject.packageDependenciesAreOutdated(at: projectDirectory)

            // Then
            XCTAssertFalse(got)
        }
    }

    func test_packageDependenciesAreOutdated_whenPackageResolvedMatchesCustomScratchDirectory() async throws {
        try await withMockedEnvironment {
            // Given
            let projectDirectory = try temporaryPath()
            let packagePath = projectDirectory.appending(
                components: Constants.tuistDirectoryName,
                Constants.SwiftPackageManager.packageSwiftName
            )
            let packageDirectory = packagePath.parentDirectory
            let scratchDirectory = try temporaryPath().appending(components: "CustomScratch")
            let customConfigLoader = MockConfigLoading()
            given(manifestFilesLocator)
                .locatePackageManifest(at: .any)
                .willReturn(packagePath)
            given(customConfigLoader)
                .loadConfig(path: .any)
                .willReturn(
                    .test(
                        project: .generated(
                            .test(
                                installOptions: .test(
                                    passthroughSwiftPackageManagerArguments: [
                                        "--scratch-path",
                                        scratchDirectory.pathString,
                                    ]
                                )
                            )
                        )
                    )
                )
            let subject = OutdatedDependenciesChecker(
                manifestFilesLocator: manifestFilesLocator,
                fileSystem: FileSystem(),
                configLoader: customConfigLoader
            )

            let currentPackageResolvedPath = packageDirectory.appending(
                component: Constants.SwiftPackageManager.packageResolvedName
            )
            let savedPackageResolvedPath = scratchDirectory.appending(components: [
                Constants.DerivedDirectory.name,
                Constants.SwiftPackageManager.packageResolvedName,
            ])
            try await fileSystem.makeDirectory(at: currentPackageResolvedPath.parentDirectory)
            try await fileSystem.writeText("resolved", at: currentPackageResolvedPath)
            try await fileSystem.makeDirectory(at: savedPackageResolvedPath.parentDirectory)
            try await fileSystem.writeText("resolved", at: savedPackageResolvedPath)

            // When
            let got = try await subject.packageDependenciesAreOutdated(at: projectDirectory)

            // Then
            XCTAssertFalse(got)
        }
    }
}
