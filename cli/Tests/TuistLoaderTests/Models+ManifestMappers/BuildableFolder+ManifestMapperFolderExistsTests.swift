import FileSystem
import FileSystemTesting
import Foundation
import Path
import ProjectDescription
import Testing
import XcodeGraph
@testable import TuistLoader

struct BuildableFolderManifestMapperFolderExistsTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory) func from_whenFolderDoesNotExist_throwsBuildableFolderNotFound() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let folderPath = temporaryDirectory.appending(component: "NonExistingFolder")
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryDirectory,
            rootDirectory: temporaryDirectory
        )
        let manifest = ProjectDescription.BuildableFolder.folder(.path(folderPath.pathString))

        await #expect(throws: BuildableFolderManifestMapperError.folderNotFound(targetName: "Target", path: folderPath)) {
            try await XcodeGraph.BuildableFolder.from(
                manifest: manifest,
                generatorPaths: generatorPaths,
                targetName: "Target"
            )
        }
    }

    @Test(.inTemporaryDirectory) func from_whenFolderExists_mapsCorrectly() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let folderPath = temporaryDirectory.appending(component: "ExistingFolder")
        try await fileSystem.makeDirectory(at: folderPath)
        let fileAPath = folderPath.appending(component: "A.swift")
        try await fileSystem.touch(fileAPath)

        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryDirectory,
            rootDirectory: temporaryDirectory
        )
        let manifest = ProjectDescription.BuildableFolder.folder(.path(folderPath.pathString))

        let got = try await XcodeGraph.BuildableFolder.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            targetName: "Target"
        )

        #expect(got.path == folderPath)
        #expect(got.resolvedFiles.count == 1)
        #expect(got.resolvedFiles.first?.path == fileAPath)
    }
}
