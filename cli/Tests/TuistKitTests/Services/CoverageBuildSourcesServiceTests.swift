import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistConfig
import TuistCore
import TuistEnvironment
import TuistGit
import TuistRootDirectoryLocator
import TuistTesting

@testable import TuistKit

struct CoverageBuildSourcesServiceTests {
    private let gitController = MockGitControlling()
    private let rootDirectoryLocator = MockRootDirectoryLocating()
    private let fileSystem = FileSystem()
    private let subject: CoverageBuildSourcesService

    init() {
        subject = CoverageBuildSourcesService(
            fileSystem: fileSystem,
            gitController: gitController,
            rootDirectoryLocator: rootDirectoryLocator
        )
    }

    @Test func root_isTheGitTopLevelElseTheManifestsRoot() async throws {
        let directory = try AbsolutePath(validating: "/checkout/App")
        given(gitController).isInGitRepository(workingDirectory: .value(directory)).willReturn(true)
        given(gitController).topLevelGitDirectory(workingDirectory: .value(directory))
            .willReturn(try AbsolutePath(validating: "/checkout"))
        let inRepository = try await subject.root(from: directory)
        #expect(inRepository?.root == (try AbsolutePath(validating: "/checkout")))
        #expect(inRepository?.inRepository == true)

        let elsewhere = try AbsolutePath(validating: "/elsewhere/App")
        given(gitController).isInGitRepository(workingDirectory: .value(elsewhere)).willReturn(false)
        given(rootDirectoryLocator).locate(from: .value(elsewhere)).willReturn(try AbsolutePath(validating: "/elsewhere"))
        let located = try await subject.root(from: elsewhere)
        #expect(located?.root == (try AbsolutePath(validating: "/elsewhere")))
        #expect(located?.inRepository == false)

        let nowhere = try AbsolutePath(validating: "/nowhere")
        given(gitController).isInGitRepository(workingDirectory: .value(nowhere)).willReturn(false)
        given(rootDirectoryLocator).locate(from: .value(nowhere)).willReturn(nil)
        #expect(try await subject.root(from: nowhere) == nil)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func write_recordsTheBuildCheckoutForTheTestRun() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testProductsPath = temporaryDirectory.appending(component: "App.xctestproducts")
        try await fileSystem.makeDirectory(at: testProductsPath)
        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(true)
        given(gitController)
            .topLevelGitDirectory(workingDirectory: .any)
            .willReturn(try AbsolutePath(validating: "/build-machine/checkout"))
        given(gitController)
            .sourceFileBlobIds(workingDirectory: .any, pathExtensions: .any)
            .willReturn(["Sources/A.swift": "aaa"])

        await subject.write(to: testProductsPath, config: .test(fullHandle: "tuist/tuist"))

        // The test run restores what the build recorded.
        let storage = RunMetadataStorage()
        await storage.restoreCoverageBuildSources(from: testProductsPath)
        #expect(await storage.coverageBuildSources == CoverageBuildSources(
            rootDirectories: ["/build-machine/checkout", "/TUIST_SOURCE_ROOT"],
            files: ["Sources/A.swift": "aaa"]
        ))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func record_keepsTheTargetsForTheRunAndWriteCarriesThemOver() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testProductsPath = temporaryDirectory.appending(component: "App.xctestproducts")
        try await fileSystem.makeDirectory(at: testProductsPath)
        given(gitController).isInGitRepository(workingDirectory: .any).willReturn(true)
        given(gitController)
            .topLevelGitDirectory(workingDirectory: .any)
            .willReturn(try AbsolutePath(validating: "/checkout"))
        given(gitController).sourceFileBlobIds(workingDirectory: .any, pathExtensions: .any).willReturn([:])
        let storage = RunMetadataStorage()

        try await RunMetadataStorage.$current.withValue(storage) {
            await subject.record(config: .test(fullHandle: "tuist/tuist"), targets: [
                CoverageBuildTarget(
                    name: "Lib.framework",
                    isTest: false,
                    files: ["/checkout/Sources/Lib/A.swift", "/elsewhere/B.swift"]
                ),
            ])
            await subject.write(to: testProductsPath, config: .test(fullHandle: "tuist/tuist"))
        }

        let expected = CoverageBuildSources(
            rootDirectories: ["/checkout", "/TUIST_SOURCE_ROOT"],
            files: [:],
            targets: [CoverageBuildTarget(
                name: "Lib.framework",
                isTest: false,
                files: ["Sources/Lib/A.swift", "/elsewhere/B.swift"]
            )]
        )
        #expect(await storage.coverageBuildSources == expected)
        let restored = RunMetadataStorage()
        await restored.restoreCoverageBuildSources(from: testProductsPath)
        #expect(await restored.coverageBuildSources == expected)
        #expect(await restored.testProductsPath == testProductsPath)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func write_removesAnEarlierRecordWhenCoverageUploadIsOff() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testProductsPath = temporaryDirectory.appending(component: "App.xctestproducts")
        try await fileSystem.makeDirectory(at: testProductsPath)
        let sourcesPath = testProductsPath.appending(component: CoverageBuildSources.fileName)
        try await fileSystem.writeText("{}", at: sourcesPath)

        await subject.write(to: testProductsPath, config: .test(fullHandle: "tuist/tuist"))

        #expect(try await !fileSystem.exists(sourcesPath))
        verify(gitController)
            .sourceFileBlobIds(workingDirectory: .any, pathExtensions: .any)
            .called(0)
    }
}
