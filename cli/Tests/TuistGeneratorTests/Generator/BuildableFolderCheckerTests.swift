import FileSystem
import Path
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

    static let declaredContentsCases: [(Set<BuildableFolderContent>, Bool, Bool)] = [
        ([], false, false),
        ([.sources], true, false),
        ([.resources], false, true),
        ([.sources, .resources], true, true),
    ]

    @Test(arguments: declaredContentsCases)
    func declaredContents_ignoreFilesOnDisk(
        contents: Set<BuildableFolderContent>,
        sources: Bool,
        resources: Bool
    ) async throws {
        let folderPath = try AbsolutePath(validating: "/project/Generated")
        let empty = BuildableFolder(
            path: folderPath,
            exceptions: BuildableFolderExceptions(exceptions: []),
            resolvedFiles: [],
            contents: contents
        )
        let filled = BuildableFolder(
            path: folderPath,
            exceptions: BuildableFolderExceptions(exceptions: []),
            resolvedFiles: [
                BuildableFolderFile(path: folderPath.appending(component: "A.swift"), compilerFlags: nil),
                BuildableFolderFile(path: folderPath.appending(component: "A.json"), compilerFlags: nil),
            ],
            contents: contents
        )

        for folder in [empty, filled] {
            #expect(try await subject.containsSources([folder]) == sources)
            #expect(try await subject.containsResources([folder]) == resources)
        }
    }
}

enum ResourceExtension: String, CaseIterable {
    case txt
    case json
    case js
    // Files with these extensions used to slip through the legacy resource allowlist —
    // covered here to lock in Xcode's "anything not source/header is a resource" behavior.
    case jpg
    case png
    case ttf
    case heic
    case aar
    case weirdext
}
