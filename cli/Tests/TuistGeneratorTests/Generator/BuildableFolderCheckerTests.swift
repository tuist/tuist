import FileSystem
import Testing
import TuistGenerator
import XcodeGraph

struct BuildableFolderCheckerTests {
    let subject = BuildableFolderChecker()
    let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory) func containsSources_when_containsSources() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let sourceFilePath = temporaryDirectory.appending(component: "File.swift")
        try await fileSystem.touch(sourceFilePath)

        let got = try await subject.containsSources([BuildableFolder(
            path: temporaryDirectory,
            exceptions: BuildableFolderExceptions(exceptions: []),
            resolvedFiles: [BuildableFolderFile(path: sourceFilePath, compilerFlags: nil)]
        )])

        #expect(got == true)
    }

    @Test(.inTemporaryDirectory) func containsSources_when_doesntContainSources() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xccstringFile = temporaryDirectory.appending(component: "File.xcstrings")
        try await fileSystem.touch(xccstringFile)

        let got = try await subject.containsSources([BuildableFolder(
            path: temporaryDirectory,
            exceptions: BuildableFolderExceptions(exceptions: []),
            resolvedFiles: [BuildableFolderFile(path: xccstringFile, compilerFlags: nil)]
        )])

        #expect(got == false)
    }

    @Test(.inTemporaryDirectory, arguments: ResourceExtension.allCases)
    func containsResources_when_containsResources(resourceExtension: ResourceExtension) async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileExtension = resourceExtension.rawValue
        let resourceFilePath = temporaryDirectory.appending(component: "File.\(fileExtension)")
        try await fileSystem.touch(resourceFilePath)

        let got = try await subject.containsResources([BuildableFolder(
            path: temporaryDirectory,
            exceptions: BuildableFolderExceptions(exceptions: []),
            resolvedFiles: [BuildableFolderFile(path: resourceFilePath, compilerFlags: nil)]
        )])

        #expect(got == true)
    }

    @Test(.inTemporaryDirectory) func containsResources_when_doesntContainResources() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let sourceFilePath = temporaryDirectory.appending(component: "File.swift")
        try await fileSystem.touch(sourceFilePath)

        let got = try await subject.containsResources([BuildableFolder(
            path: temporaryDirectory,
            exceptions: BuildableFolderExceptions(exceptions: []),
            resolvedFiles: [BuildableFolderFile(path: sourceFilePath, compilerFlags: nil)]
        )])

        #expect(got == false)
    }
}

enum ResourceExtension: String, CaseIterable {
    case txt
    case json
    case js
}
