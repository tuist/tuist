import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import struct TSCUtility.Version
import TuistCore
import TuistHasher
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistCache

struct ContentHashingIntegrationTests {
    var subject: CacheGraphContentHasher!
    var temporaryDirectoryPath: String!
    var source1: SourceFile!
    var source2: SourceFile!
    var source3: SourceFile!
    var source4: SourceFile!
    var resourceFile1: ResourceFileElement!
    var resourceFile2: ResourceFileElement!
    var resourceFolderReference1: ResourceFileElement!
    var resourceFolderReference2: ResourceFileElement!
    var coreDataModel1: CoreDataModel!
    var coreDataModel2: CoreDataModel!

    init() throws {
        let temporaryDirectoryPath = try #require(FileSystem.temporaryTestDirectory)
        source1 = try createTemporarySourceFile(on: temporaryDirectoryPath, name: "1", content: "1")
        source2 = try createTemporarySourceFile(on: temporaryDirectoryPath, name: "2", content: "2")
        source3 = try createTemporarySourceFile(on: temporaryDirectoryPath, name: "3", content: "3")
        source4 = try createTemporarySourceFile(on: temporaryDirectoryPath, name: "4", content: "4")
        resourceFile1 = try createTemporaryResourceFile(on: temporaryDirectoryPath, name: "r1", content: "r1")
        resourceFile2 = try createTemporaryResourceFile(on: temporaryDirectoryPath, name: "r2", content: "r2")
        resourceFolderReference1 = try createTemporaryResourceFolderReference(
            on: temporaryDirectoryPath,
            name: "rf1",
            content: "rf1"
        )
        resourceFolderReference2 = try createTemporaryResourceFolderReference(
            on: temporaryDirectoryPath,
            name: "rf2",
            content: "rf2"
        )
        _ = try createTemporarySourceFile(on: temporaryDirectoryPath, name: "CoreDataModel1", content: "cd1")
        _ = try createTemporarySourceFile(on: temporaryDirectoryPath, name: "CoreDataModel2", content: "cd2")
        _ = try createTemporarySourceFile(on: temporaryDirectoryPath, name: "Info.plist", content: "plist")
        coreDataModel1 = CoreDataModel(
            path: temporaryDirectoryPath.appending(component: "CoreDataModel1"),
            versions: [],
            currentVersion: "1"
        )
        coreDataModel2 = CoreDataModel(
            path: temporaryDirectoryPath.appending(component: "CoreDataModel2"),
            versions: [],
            currentVersion: "2"
        )

        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock).swiftlangVersion().willReturn("5.4.0")
        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selectedVersion()
            .willReturn(Version(15, 3, 0))
        subject = CacheGraphContentHasher(contentHasher: CachedContentHasher())
    }

    // MARK: - Sources

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController
    ) func contentHashes_frameworksWithSameSources() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let framework1Target = makeFramework(sources: [source1, source2])
        let framework2Target = makeFramework(sources: [source2, source1])
        let project1 = Project.test(
            path: temporaryPath.appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: temporaryPath.appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let contentHash = try await subject.contentHashes(
            for: graph,
            configuration: "Debug",
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )

        // Then
        #expect(contentHash[framework1] == contentHash[framework2])
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController
    ) func contentHashes_frameworksWithDifferentSources() async throws {
        // Given
        let framework1Target = makeFramework(sources: [source1, source2])
        let framework2Target = makeFramework(sources: [source3, source4])
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let project1 = Project.test(
            path: temporaryPath.appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: temporaryPath.appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let contentHash = try await subject.contentHashes(
            for: graph,
            configuration: "Debug",
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )

        // Then
        #expect(contentHash[framework1] != contentHash[framework2])
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController
    ) func contentHashes_xctestSupportFrameworkUsedByTestsIsComputed() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let testSupportTarget = makeFramework(
            name: "TestSupport",
            sources: [source1],
            dependencies: [.xctest]
        )
        let featureTarget = makeFramework(
            name: "Feature",
            sources: [source2]
        )
        let testsTarget = Target.test(
            name: "FeatureTests",
            product: .unitTests,
            dependencies: [
                .target(name: featureTarget.name),
                .target(name: testSupportTarget.name),
            ]
        )
        let project = Project.test(
            path: temporaryPath.appending(component: "Project"),
            settings: .default,
            targets: [testSupportTarget, featureTarget, testsTarget]
        )
        let testSupport = GraphTarget(
            path: project.path,
            target: project.targets["TestSupport"]!,
            project: project
        )
        let feature = GraphTarget(
            path: project.path,
            target: project.targets["Feature"]!,
            project: project
        )
        let tests = GraphTarget(
            path: project.path,
            target: project.targets["FeatureTests"]!,
            project: project
        )
        let graph = Graph.test(
            projects: [
                project.path: project,
            ],
            dependencies: [
                .target(name: testSupportTarget.name, path: project.path): [
                    .testSDK(name: "XCTest.framework"),
                ],
                .target(name: testsTarget.name, path: project.path): [
                    .target(name: featureTarget.name, path: project.path),
                    .target(name: testSupportTarget.name, path: project.path),
                ],
            ]
        )

        // When
        let contentHash = try await subject.contentHashes(
            for: graph,
            configuration: "Debug",
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )

        // Then
        #expect(contentHash[testSupport] != nil)
        #expect(contentHash[feature] != nil)
        #expect(contentHash[tests] == nil)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController
    ) func contentHashes_librariesAreComputed() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let staticLibraryTarget = makeLibrary(
            name: "StaticLibrary",
            product: .staticLibrary,
            sources: [source1]
        )
        let dynamicLibraryTarget = makeLibrary(
            name: "DynamicLibrary",
            product: .dynamicLibrary,
            sources: [source2]
        )
        let project = Project.test(
            path: temporaryPath.appending(component: "Project"),
            settings: .default,
            targets: [staticLibraryTarget, dynamicLibraryTarget]
        )
        let staticLibrary = GraphTarget(
            path: project.path,
            target: project.targets["StaticLibrary"]!,
            project: project
        )
        let dynamicLibrary = GraphTarget(
            path: project.path,
            target: project.targets["DynamicLibrary"]!,
            project: project
        )
        let graph = Graph.test(
            projects: [
                project.path: project,
            ]
        )

        // When
        let contentHash = try await subject.contentHashes(
            for: graph,
            configuration: "Debug",
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )

        // Then
        #expect(contentHash[staticLibrary] != nil)
        #expect(contentHash[dynamicLibrary] != nil)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController
    ) func contentHashes_removingUnselectedConfigurationDoesNotChangeHash() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let selectedConfiguration = BuildConfiguration.debug("Debug-SharedCache")
        let unrelatedConfiguration = BuildConfiguration.debug("Debug-AppVariant-B")
        let selectedSettings = Configuration(settings: ["SWIFT_VERSION": "5.10"])
        let settingsWithUnrelatedConfiguration = Settings.test(
            configurations: [
                selectedConfiguration: selectedSettings,
                unrelatedConfiguration: Configuration(settings: ["UNRELATED": "YES"]),
            ]
        )
        let settingsWithoutUnrelatedConfiguration = Settings.test(
            configurations: [
                selectedConfiguration: selectedSettings,
            ]
        )
        let frameworkWithUnrelatedConfiguration = makeFramework(
            settings: settingsWithUnrelatedConfiguration,
            sources: [source1]
        )
        let frameworkWithoutUnrelatedConfiguration = makeFramework(
            settings: settingsWithoutUnrelatedConfiguration,
            sources: [source1]
        )
        let projectWithUnrelatedConfiguration = Project.test(
            path: temporaryPath.appending(component: "with-unrelated-configuration"),
            settings: settingsWithUnrelatedConfiguration,
            targets: [frameworkWithUnrelatedConfiguration]
        )
        let projectWithoutUnrelatedConfiguration = Project.test(
            path: temporaryPath.appending(component: "without-unrelated-configuration"),
            settings: settingsWithoutUnrelatedConfiguration,
            targets: [frameworkWithoutUnrelatedConfiguration]
        )
        let graphWithUnrelatedConfiguration = Graph.test(
            projects: [projectWithUnrelatedConfiguration.path: projectWithUnrelatedConfiguration]
        )
        let graphWithoutUnrelatedConfiguration = Graph.test(
            projects: [projectWithoutUnrelatedConfiguration.path: projectWithoutUnrelatedConfiguration]
        )
        let graphTargetWithUnrelatedConfiguration = GraphTarget(
            path: projectWithUnrelatedConfiguration.path,
            target: frameworkWithUnrelatedConfiguration,
            project: projectWithUnrelatedConfiguration
        )
        let graphTargetWithoutUnrelatedConfiguration = GraphTarget(
            path: projectWithoutUnrelatedConfiguration.path,
            target: frameworkWithoutUnrelatedConfiguration,
            project: projectWithoutUnrelatedConfiguration
        )

        // When
        let hashesWithUnrelatedConfiguration = try await subject.contentHashes(
            for: graphWithUnrelatedConfiguration,
            configuration: selectedConfiguration.name,
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )
        let hashesWithoutUnrelatedConfiguration = try await subject.contentHashes(
            for: graphWithoutUnrelatedConfiguration,
            configuration: selectedConfiguration.name,
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )

        // Then
        #expect(
            hashesWithUnrelatedConfiguration[graphTargetWithUnrelatedConfiguration]?.hash
                == hashesWithoutUnrelatedConfiguration[graphTargetWithoutUnrelatedConfiguration]?.hash
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController
    ) func contentHashes_changingSelectedConfigurationChangesHash() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let selectedConfiguration = BuildConfiguration.debug("Debug-SharedCache")
        let firstSettings = Settings.test(
            configurations: [
                selectedConfiguration: Configuration(settings: ["SWIFT_VERSION": "5.9"]),
            ]
        )
        let secondSettings = Settings.test(
            configurations: [
                selectedConfiguration: Configuration(settings: ["SWIFT_VERSION": "6.0"]),
            ]
        )
        let firstFramework = makeFramework(settings: firstSettings, sources: [source1])
        let secondFramework = makeFramework(settings: secondSettings, sources: [source1])
        let firstProject = Project.test(
            path: temporaryPath.appending(component: "first-selected-configuration"),
            settings: firstSettings,
            targets: [firstFramework]
        )
        let secondProject = Project.test(
            path: temporaryPath.appending(component: "second-selected-configuration"),
            settings: secondSettings,
            targets: [secondFramework]
        )
        let firstGraph = Graph.test(projects: [firstProject.path: firstProject])
        let secondGraph = Graph.test(projects: [secondProject.path: secondProject])
        let firstGraphTarget = GraphTarget(path: firstProject.path, target: firstFramework, project: firstProject)
        let secondGraphTarget = GraphTarget(path: secondProject.path, target: secondFramework, project: secondProject)

        // When
        let firstHashes = try await subject.contentHashes(
            for: firstGraph,
            configuration: selectedConfiguration.name,
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )
        let secondHashes = try await subject.contentHashes(
            for: secondGraph,
            configuration: selectedConfiguration.name,
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )

        // Then
        #expect(firstHashes[firstGraphTarget]?.hash != secondHashes[secondGraphTarget]?.hash)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController
    ) func contentHashes_baseDebugSettingsOnlyAffectDebugConfiguration() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let projectSettings = Settings.default
        let firstTargetSettings = Settings.test(
            baseDebug: ["ENABLE_TESTING_SEARCH_PATHS": "YES"]
        )
        let secondTargetSettings = Settings.test(
            baseDebug: ["ENABLE_TESTING_SEARCH_PATHS": "NO"]
        )
        let firstFramework = makeFramework(settings: firstTargetSettings, sources: [source1])
        let secondFramework = makeFramework(settings: secondTargetSettings, sources: [source1])
        let firstProject = Project.test(
            path: temporaryPath.appending(component: "first-base-debug"),
            settings: projectSettings,
            targets: [firstFramework]
        )
        let secondProject = Project.test(
            path: temporaryPath.appending(component: "second-base-debug"),
            settings: projectSettings,
            targets: [secondFramework]
        )
        let firstGraph = Graph.test(projects: [firstProject.path: firstProject])
        let secondGraph = Graph.test(projects: [secondProject.path: secondProject])
        let firstGraphTarget = GraphTarget(path: firstProject.path, target: firstFramework, project: firstProject)
        let secondGraphTarget = GraphTarget(path: secondProject.path, target: secondFramework, project: secondProject)

        // When
        let firstDebugHashes = try await subject.contentHashes(
            for: firstGraph,
            configuration: BuildConfiguration.debug.name,
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )
        let secondDebugHashes = try await subject.contentHashes(
            for: secondGraph,
            configuration: BuildConfiguration.debug.name,
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )
        let firstReleaseHashes = try await subject.contentHashes(
            for: firstGraph,
            configuration: BuildConfiguration.release.name,
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )
        let secondReleaseHashes = try await subject.contentHashes(
            for: secondGraph,
            configuration: BuildConfiguration.release.name,
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )

        // Then
        #expect(firstDebugHashes[firstGraphTarget]?.hash != secondDebugHashes[secondGraphTarget]?.hash)
        #expect(firstReleaseHashes[firstGraphTarget]?.hash == secondReleaseHashes[secondGraphTarget]?.hash)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController
    ) func contentHashes_hashIsConsistent() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let framework1Target = makeFramework(sources: [source1, source2])
        let framework2Target = makeFramework(sources: [source3, source4])
        let project1 = Project.test(
            path: temporaryPath.appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: temporaryPath.appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let firstRun = try await subject.contentHashes(
            for: graph,
            configuration: "Debug",
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )
        let secondRun = try await subject.contentHashes(
            for: graph,
            configuration: "Debug",
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )

        // Then
        #expect(firstRun[framework1]?.hash == "ddb2a8a0a4663353ae43079cdf358016")
        #expect(firstRun[framework2]?.hash == "bea9417f35911c3c83609e16fcfb8c36")
        #expect(firstRun[framework1]?.hash == secondRun[framework1]?.hash)
        #expect(firstRun[framework2]?.hash == secondRun[framework2]?.hash)
        #expect(firstRun[framework1]?.hash != firstRun[framework2]?.hash)
    }

    // MARK: - Resources

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController
    ) func contentHashes_differentResourceFiles() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let framework1Target = makeFramework(resources: .init([resourceFile1]))
        let framework2Target = makeFramework(resources: .init([resourceFile2]))
        let project1 = Project.test(
            path: temporaryPath.appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: temporaryPath.appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let contentHash = try await subject.contentHashes(
            for: graph,
            configuration: "Debug",
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )

        // Then
        #expect(contentHash[framework1] != contentHash[framework2])
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController
    ) func contentHashes_differentResourcesFolderReferences() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let framework1Target = makeFramework(resources: .init([resourceFolderReference1]))
        let framework2Target = makeFramework(resources: .init([resourceFolderReference2]))
        let project1 = Project.test(
            path: temporaryPath.appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: temporaryPath.appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let contentHash = try await subject.contentHashes(
            for: graph,
            configuration: "Debug",
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )

        // Then
        #expect(contentHash[framework1] != contentHash[framework2])
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController
    ) func contentHashes_sameResources() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let resources: ResourceFileElements = .init([resourceFile1, resourceFolderReference1])
        let framework1Target = makeFramework(resources: resources)
        let framework2Target = makeFramework(resources: resources)
        let project1 = Project.test(
            path: temporaryPath.appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: temporaryPath.appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let contentHash = try await subject.contentHashes(
            for: graph,
            configuration: "Debug",
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )

        // Then
        #expect(contentHash[framework1] == contentHash[framework2])
    }

    // MARK: - Core Data Models

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController
    ) func contentHashes_differentCoreDataModels() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let framework1Target = makeFramework(coreDataModels: [coreDataModel1])
        let framework2Target = makeFramework(coreDataModels: [coreDataModel2])
        let project1 = Project.test(
            path: temporaryPath.appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: temporaryPath.appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let contentHash = try await subject.contentHashes(
            for: graph,
            configuration: "Debug",
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )

        // Then
        #expect(contentHash[framework1] != contentHash[framework2])
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController
    ) func contentHashes_sameCoreDataModels() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let framework1Target = makeFramework(coreDataModels: [coreDataModel1])
        let framework2Target = makeFramework(coreDataModels: [coreDataModel1])
        let project1 = Project.test(
            path: temporaryPath.appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: temporaryPath.appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let contentHash = try await subject.contentHashes(
            for: graph,
            configuration: "Debug",
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )

        // Then
        #expect(contentHash[framework1] == contentHash[framework2])
    }

    // MARK: - Target Actions

    // MARK: - Platform

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController
    ) func contentHashes_differentPlatform() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let framework1Target = makeFramework(platform: .iOS)
        let framework2Target = makeFramework(platform: .macOS)
        let project1 = Project.test(
            path: temporaryPath.appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: temporaryPath.appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let contentHash = try await subject.contentHashes(
            for: graph,
            configuration: "Debug",
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )

        #expect(contentHash[framework1] != contentHash[framework2])
    }

    // MARK: - ProductName

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController
    ) func contentHashes_differentProductName() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let framework1Target = makeFramework(productName: "1")
        let framework2Target = makeFramework(productName: "2")
        let project1 = Project.test(
            path: temporaryPath.appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: temporaryPath.appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let contentHash = try await subject.contentHashes(
            for: graph,
            configuration: "Debug",
            defaultConfiguration: nil,
            excludedTargets: [],
            destination: nil
        )

        #expect(contentHash[framework1] != contentHash[framework2])
    }

    // MARK: - Private helpers

    private func createTemporarySourceFile(
        on temporaryDirectoryPath: AbsolutePath,
        name: String,
        content: String
    ) throws -> SourceFile {
        let filePath = temporaryDirectoryPath.appending(component: name)
        try Data(content.utf8).write(to: filePath.url)
        return SourceFile(path: filePath, compilerFlags: nil)
    }

    private func createTemporaryResourceFile(
        on temporaryDirectoryPath: AbsolutePath,
        name: String,
        content: String
    ) throws -> ResourceFileElement {
        let filePath = temporaryDirectoryPath.appending(component: name)
        try Data(content.utf8).write(to: filePath.url)
        return ResourceFileElement.file(path: filePath)
    }

    private func createTemporaryResourceFolderReference(
        on temporaryDirectoryPath: AbsolutePath,
        name: String,
        content: String
    ) throws -> ResourceFileElement {
        let filePath = temporaryDirectoryPath.appending(component: name)
        try Data(content.utf8).write(to: filePath.url)
        return ResourceFileElement.folderReference(path: filePath)
    }

    private func makeFramework(
        name: String = "Target",
        platform: Platform = .iOS,
        productName: String? = nil,
        settings: Settings? = .test(),
        sources: [SourceFile] = [],
        resources: ResourceFileElements = .init([]),
        coreDataModels: [CoreDataModel] = [],
        targetScripts: [TargetScript] = [],
        dependencies: [TargetDependency] = []
    ) -> Target {
        .test(
            name: name,
            platform: platform,
            product: .framework,
            productName: productName,
            settings: settings,
            sources: sources,
            resources: resources,
            coreDataModels: coreDataModels,
            scripts: targetScripts,
            dependencies: dependencies
        )
    }

    private func makeLibrary(
        name: String,
        product: Product,
        sources: [SourceFile] = []
    ) -> Target {
        .test(
            name: name,
            product: product,
            sources: sources
        )
    }
}
