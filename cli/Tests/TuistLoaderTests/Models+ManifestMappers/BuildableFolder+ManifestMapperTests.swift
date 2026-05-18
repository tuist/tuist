import FileSystem
import FileSystemTesting
import Foundation
import Path
import ProjectDescription
import Testing
import TuistCore
import XcodeGraph
@testable import TuistLoader
@testable import TuistTesting

struct BuildableFolderManifestMapperTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory) func from_withGlobExclusionPattern_excludesMatchingFiles() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        try await fileSystem.makeDirectory(at: temporaryDirectory.appending(component: "Sources"))
        try await fileSystem.touch(temporaryDirectory.appending(components: "Sources", "File.swift"))
        try await fileSystem.touch(temporaryDirectory.appending(components: "Sources", "TestData.json"))
        try await fileSystem.touch(temporaryDirectory.appending(components: "Sources", "AnotherData.json"))

        let manifest = ProjectDescription.BuildableFolder.folder(
            .path(temporaryDirectory.pathString),
            exceptions: .exceptions([
                .exception(excluded: ["**/*.json"]),
            ])
        )

        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryDirectory,
            rootDirectory: temporaryDirectory
        )

        let got = try #require(try await XcodeGraph.BuildableFolder.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            targetName: "Target"
        ))

        let resolvedPaths = Set(got.resolvedFiles.map(\.path))

        #expect(resolvedPaths.contains(temporaryDirectory.appending(components: "Sources", "File.swift")))
        #expect(!resolvedPaths.contains(temporaryDirectory.appending(components: "Sources", "TestData.json")))
        #expect(!resolvedPaths.contains(temporaryDirectory.appending(components: "Sources", "AnotherData.json")))
    }

    @Test(.inTemporaryDirectory) func from_withLiteralExclusionPattern_excludesSpecificFile() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        try await fileSystem.makeDirectory(at: temporaryDirectory.appending(component: "Sources"))
        try await fileSystem.touch(temporaryDirectory.appending(components: "Sources", "File.swift"))
        try await fileSystem.touch(temporaryDirectory.appending(components: "Sources", "Excluded.swift"))

        let manifest = ProjectDescription.BuildableFolder.folder(
            .path(temporaryDirectory.pathString),
            exceptions: .exceptions([
                .exception(excluded: ["Sources/Excluded.swift"]),
            ])
        )

        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryDirectory,
            rootDirectory: temporaryDirectory
        )

        let got = try #require(try await XcodeGraph.BuildableFolder.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            targetName: "Target"
        ))

        let resolvedPaths = Set(got.resolvedFiles.map(\.path))

        #expect(resolvedPaths.contains(temporaryDirectory.appending(components: "Sources", "File.swift")))
        #expect(!resolvedPaths.contains(temporaryDirectory.appending(components: "Sources", "Excluded.swift")))
    }

    @Test(.inTemporaryDirectory) func from_withNoExclusions_includesAllFiles() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        try await fileSystem.makeDirectory(at: temporaryDirectory.appending(component: "Sources"))
        try await fileSystem.touch(temporaryDirectory.appending(components: "Sources", "File.swift"))
        try await fileSystem.touch(temporaryDirectory.appending(components: "Sources", "Helper.swift"))
        try await fileSystem.touch(temporaryDirectory.appending(components: "Sources", "Data.json"))

        let manifest = ProjectDescription.BuildableFolder.folder(
            .path(temporaryDirectory.pathString),
            exceptions: .exceptions([])
        )

        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryDirectory,
            rootDirectory: temporaryDirectory
        )

        let got = try #require(try await XcodeGraph.BuildableFolder.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            targetName: "Target"
        ))

        let resolvedPaths = Set(got.resolvedFiles.map(\.path))

        #expect(resolvedPaths.contains(temporaryDirectory.appending(components: "Sources", "File.swift")))
        #expect(resolvedPaths.contains(temporaryDirectory.appending(components: "Sources", "Helper.swift")))
        #expect(resolvedPaths.contains(temporaryDirectory.appending(components: "Sources", "Data.json")))
    }

    @Test(.inTemporaryDirectory) func from_excludesDirectoriesFromResolvedFiles() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let sourcesPath = temporaryDirectory.appending(component: "Sources")
        try await fileSystem.makeDirectory(at: sourcesPath.appending(component: "Services"))
        try await fileSystem.touch(sourcesPath.appending(components: "Services", "Service.swift"))
        try await fileSystem.touch(sourcesPath.appending(components: "Root.swift"))

        let manifest = ProjectDescription.BuildableFolder.folder(
            .path(temporaryDirectory.pathString),
            exceptions: .exceptions([])
        )

        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryDirectory,
            rootDirectory: temporaryDirectory
        )

        let got = try #require(try await XcodeGraph.BuildableFolder.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            targetName: "Target"
        ))

        let resolvedPaths = Set(got.resolvedFiles.map(\.path))

        #expect(resolvedPaths.contains(sourcesPath.appending(components: "Services", "Service.swift")))
        #expect(resolvedPaths.contains(sourcesPath.appending(component: "Root.swift")))
        #expect(!resolvedPaths.contains(sourcesPath))
        #expect(!resolvedPaths.contains(sourcesPath.appending(component: "Services")))
    }

    @Test(.inTemporaryDirectory) func from_withCompilerFlags_preservesFlags() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        try await fileSystem.makeDirectory(at: temporaryDirectory.appending(component: "Sources"))
        try await fileSystem.touch(temporaryDirectory.appending(components: "Sources", "File.swift"))

        let manifest = ProjectDescription.BuildableFolder.folder(
            .path(temporaryDirectory.pathString),
            exceptions: .exceptions([
                .exception(compilerFlags: ["Sources/File.swift": "-O0"]),
            ])
        )

        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryDirectory,
            rootDirectory: temporaryDirectory
        )

        let got = try #require(try await XcodeGraph.BuildableFolder.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            targetName: "Target"
        ))

        let fileWithFlags = got.resolvedFiles.first {
            $0.path == temporaryDirectory.appending(components: "Sources", "File.swift")
        }

        #expect(fileWithFlags?.compilerFlags == "-O0")
    }

    @Test(.inTemporaryDirectory) func from_treatsOpaqueDirectoriesAsFiles() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let sourcesPath = temporaryDirectory.appending(component: "Sources")
        let xcassetsPath = sourcesPath.appending(component: "Assets.xcassets")
        try await fileSystem.makeDirectory(at: xcassetsPath.appending(component: "AccentColor.colorset"))
        try await fileSystem.touch(xcassetsPath.appending(components: "AccentColor.colorset", "Contents.json"))
        try await fileSystem.touch(xcassetsPath.appending(component: "Contents.json"))
        try await fileSystem.touch(sourcesPath.appending(component: "File.swift"))

        let manifest = ProjectDescription.BuildableFolder.folder(
            .path(temporaryDirectory.pathString),
            exceptions: .exceptions([])
        )

        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryDirectory,
            rootDirectory: temporaryDirectory
        )

        let got = try #require(try await XcodeGraph.BuildableFolder.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            targetName: "Target"
        ))

        let resolvedPaths = Set(got.resolvedFiles.map(\.path))

        #expect(resolvedPaths.contains(xcassetsPath))
        #expect(resolvedPaths.contains(sourcesPath.appending(component: "File.swift")))
        #expect(!resolvedPaths.contains(xcassetsPath.appending(component: "Contents.json")))
        #expect(!resolvedPaths.contains(xcassetsPath.appending(components: "AccentColor.colorset", "Contents.json")))
    }

    @Test(.inTemporaryDirectory) func from_withNestedGlobPattern_excludesNestedFiles() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        try await fileSystem.makeDirectory(at: temporaryDirectory.appending(components: "Sources", "Tests", "Fixtures"))
        try await fileSystem.touch(temporaryDirectory.appending(components: "Sources", "File.swift"))
        try await fileSystem.touch(temporaryDirectory.appending(components: "Sources", "Tests", "TestFile.swift"))
        try await fileSystem.touch(temporaryDirectory.appending(components: "Sources", "Tests", "Fixtures", "data.json"))
        try await fileSystem.touch(temporaryDirectory.appending(components: "Sources", "Tests", "Fixtures", "nested.json"))

        let manifest = ProjectDescription.BuildableFolder.folder(
            .path(temporaryDirectory.pathString),
            exceptions: .exceptions([
                .exception(excluded: ["**/Fixtures/**/*.json"]),
            ])
        )

        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryDirectory,
            rootDirectory: temporaryDirectory
        )

        let got = try #require(try await XcodeGraph.BuildableFolder.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            targetName: "Target"
        ))

        let resolvedPaths = Set(got.resolvedFiles.map(\.path))

        #expect(resolvedPaths.contains(temporaryDirectory.appending(components: "Sources", "File.swift")))
        #expect(resolvedPaths.contains(temporaryDirectory.appending(components: "Sources", "Tests", "TestFile.swift")))
        #expect(!resolvedPaths.contains(temporaryDirectory.appending(components: "Sources", "Tests", "Fixtures", "data.json")))
        #expect(!resolvedPaths.contains(temporaryDirectory.appending(components: "Sources", "Tests", "Fixtures", "nested.json")))
    }
}
