import FileSystem
import FileSystemTesting
import Mockable
import TestCoverageAttribution
import Testing
import TuistConfig
import TuistConfigLoader
import TuistConstants
import TuistEnvironmentTesting
import TuistLoader

@testable import TuistKit

@Suite(.coverageAttribution)
struct OutdatedDependenciesCheckerTests {
    private let manifestFilesLocator = MockManifestFilesLocating()
    private let configLoader = MockConfigLoading()
    private let fileSystem = FileSystem()
    private let subject: OutdatedDependenciesChecker

    init() {
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .generated(.test())))

        subject = OutdatedDependenciesChecker(
            manifestFilesLocator: manifestFilesLocator,
            fileSystem: fileSystem,
            configLoader: configLoader
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

        let got = try await subject.packageDependenciesAreOutdated(at: projectDirectory)

        #expect(got == false)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func packageDependenciesAreOutdated_whenALinkedCacheEntryWasPruned() async throws {
        let projectDirectory = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = projectDirectory.appending(
            components: Constants.tuistDirectoryName,
            Constants.SwiftPackageManager.packageSwiftName
        )
        let packageDirectory = packagePath.parentDirectory
        let scratchDirectory = packageDirectory.appending(component: Constants.SwiftPackageManager.packageBuildDirectoryName)
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(packagePath)
        let savedPackageResolvedPath = scratchDirectory.appending(components: [
            Constants.DerivedDirectory.name,
            Constants.SwiftPackageManager.packageResolvedName,
        ])
        try await fileSystem.makeDirectory(at: savedPackageResolvedPath.parentDirectory)
        try await fileSystem.writeText("resolved", at: savedPackageResolvedPath)
        try await fileSystem.writeText(
            "resolved", at: packageDirectory.appending(component: Constants.SwiftPackageManager.packageResolvedName)
        )
        let cachedSource = projectDirectory.appending(components: "cache", "sources", "alamofire", "5.0.0-abc")
        let cachedArtifact = projectDirectory.appending(components: "cache", "artifacts", "firebase", "Core-abc")
        try await fileSystem.makeDirectory(at: cachedSource)
        try await fileSystem.makeDirectory(at: cachedArtifact)
        try await fileSystem.makeDirectory(at: scratchDirectory.appending(component: "checkouts"))
        try await fileSystem.makeDirectory(at: scratchDirectory.appending(components: "artifacts", "firebase"))
        try await fileSystem.createSymbolicLink(
            from: scratchDirectory.appending(components: "checkouts", "Alamofire"), to: cachedSource
        )
        try await fileSystem.createSymbolicLink(
            from: scratchDirectory.appending(components: "artifacts", "firebase", "Core"), to: cachedArtifact
        )

        #expect(try await subject.packageDependenciesAreOutdated(at: projectDirectory) == false)

        try await fileSystem.remove(cachedArtifact)

        #expect(try await subject.packageDependenciesAreOutdated(at: projectDirectory) == true)
    }
}
