import FileSystem
import FileSystemTesting
import Mockable
import Testing
import TuistConfig
import TuistConfigLoader
import TuistConstants
import TuistEnvironmentTesting
import TuistLoader
import TuistSupport

@testable import TuistKit

struct OutdatedDependenciesCheckerTests {
    private let manifestFilesLocator = MockManifestFilesLocating()
    private let configLoader = MockConfigLoading()
    private let swiftPackageManagerController = MockSwiftPackageManagerControlling()
    private let fileSystem = FileSystem()
    private let subject: OutdatedDependenciesChecker

    init() {
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .generated(.test())))
        given(swiftPackageManagerController)
            .recordsOutdatedPrebuilts(at: .any, scratchDirectory: .any)
            .willReturn(false)

        subject = OutdatedDependenciesChecker(
            manifestFilesLocator: manifestFilesLocator,
            fileSystem: fileSystem,
            configLoader: configLoader,
            swiftPackageManagerController: swiftPackageManagerController
        )
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func packageDependenciesAreOutdated_whenPackageResolvedMatchesDefaultScratchDirectory() async throws {
        let projectDirectory = try #require(FileSystem.temporaryTestDirectory)
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

        let got = try await subject.packageDependenciesAreOutdated(at: projectDirectory)

        #expect(got == false)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func packageDependenciesAreOutdated_whenPackageResolvedMatchesCustomScratchDirectory() async throws {
        let projectDirectory = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = projectDirectory.appending(
            components: Constants.tuistDirectoryName,
            Constants.SwiftPackageManager.packageSwiftName
        )
        let packageDirectory = packagePath.parentDirectory
        let scratchDirectory = projectDirectory.appending(component: "CustomScratch")
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
            fileSystem: fileSystem,
            configLoader: customConfigLoader,
            swiftPackageManagerController: swiftPackageManagerController
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

        let got = try await subject.packageDependenciesAreOutdated(at: projectDirectory)

        #expect(got == false)
        verify(swiftPackageManagerController)
            .recordsOutdatedPrebuilts(at: .value(packageDirectory), scratchDirectory: .value(scratchDirectory))
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func packageDependenciesAreOutdated_whenTheRecordedPrebuiltsAreOutdated() async throws {
        let projectDirectory = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = projectDirectory.appending(
            components: Constants.tuistDirectoryName,
            Constants.SwiftPackageManager.packageSwiftName
        )
        let packageDirectory = packagePath.parentDirectory
        let scratchDirectory = packageDirectory.appending(component: Constants.SwiftPackageManager.packageBuildDirectoryName)
        let swiftPackageManagerController = MockSwiftPackageManagerControlling()
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(packagePath)
        given(swiftPackageManagerController)
            .recordsOutdatedPrebuilts(at: .value(packageDirectory), scratchDirectory: .value(scratchDirectory))
            .willReturn(true)
        let subject = OutdatedDependenciesChecker(
            manifestFilesLocator: manifestFilesLocator,
            fileSystem: fileSystem,
            configLoader: configLoader,
            swiftPackageManagerController: swiftPackageManagerController
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

        let got = try await subject.packageDependenciesAreOutdated(at: projectDirectory)

        #expect(got == true)
    }
}
