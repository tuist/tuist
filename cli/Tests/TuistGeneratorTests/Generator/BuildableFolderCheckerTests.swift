import FileSystem
import Testing
import TuistGenerator
import XcodeGraph

struct BuildableFolderCheckerTests {
    let subject = BuildableFolderChecker()
    let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory) func containsSources_when_containsSources() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.touch(temporaryDirectory.appending(component: "File.swift"))

        let got = try await subject.containsSources([BuildableFolder(
            path: temporaryDirectory,
            exceptions: BuildableFolderExceptions(exceptions: []),
            resolvedFiles: []
        )])

        #expect(got == true)
    }

    @Test(.inTemporaryDirectory) func containsSources_when_doesntContainSources() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.touch(temporaryDirectory.appending(component: "File.xcstrings"))

        let got = try await subject.containsSources([BuildableFolder(
            path: temporaryDirectory,
            exceptions: BuildableFolderExceptions(exceptions: []),
            resolvedFiles: []
        )])

        #expect(got == false)
    }

    @Test(.inTemporaryDirectory) func containsResources_when_containsResources() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.touch(temporaryDirectory.appending(component: "File.xcstrings"))

        let got = try await subject.containsResources([BuildableFolder(
            path: temporaryDirectory,
            exceptions: BuildableFolderExceptions(exceptions: []),
            resolvedFiles: []
        )])

        #expect(got == true)
    }

    @Test(.inTemporaryDirectory) func containsResources_when_doesntContainResources() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.touch(temporaryDirectory.appending(component: "File.swift"))

        let got = try await subject.containsResources([BuildableFolder(
            path: temporaryDirectory,
            exceptions: BuildableFolderExceptions(exceptions: []),
            resolvedFiles: []
        )])

        #expect(got == false)
    }
}
