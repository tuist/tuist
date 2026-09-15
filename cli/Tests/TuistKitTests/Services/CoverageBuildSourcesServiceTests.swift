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
            rootDirectories: ["/build-machine/checkout"],
            files: ["Sources/A.swift": "aaa"]
        ))
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
