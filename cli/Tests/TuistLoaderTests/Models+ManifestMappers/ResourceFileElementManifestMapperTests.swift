import FileSystem
import FileSystemTesting
import Foundation
import Path
import ProjectDescription
import Testing
import TuistCore
import TuistSupport
import XcodeGraph

@testable import TuistLoader
@testable import TuistTesting

struct ResourceFileElementManifestMapperTests {
    private let fileSystem = FileSystem()

    @Test(
        .inTemporaryDirectory,
        .withMockedDependencies()
    ) func from_outputs_a_warning_when_the_paths_point_to_directories() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)
        try await TuistTest.createFiles(["Documentation/README.md", "Documentation/USAGE.md"])

        let manifest = ProjectDescription.ResourceFileElement.glob(pattern: "Documentation")
        let model = try await XcodeGraph.ResourceFileElement.from(
            manifest: manifest, generatorPaths: generatorPaths, fileSystem: fileSystem,
            includeFiles: { !FileHandler.shared.isFolder($0) }
        )

        let documentationPath = temporaryPath.appending(component: "Documentation").pathString
        TuistTest.expectLogs("'\(documentationPath)' is a directory, try using: '\(documentationPath)/**' to list its files")
        #expect(model == [])
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies()) func from_when_no_files_found() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)
        try await fileSystem.makeDirectory(at: temporaryPath.appending(component: "Resources"))

        let manifest = ProjectDescription.ResourceFileElement.glob(pattern: "Resources/**")
        let model = try await XcodeGraph.ResourceFileElement.from(
            manifest: manifest, generatorPaths: generatorPaths, fileSystem: fileSystem
        )

        TuistTest.doesntExpectLogs("No files found at: \(temporaryPath.appending(components: "Resources", "**"))")
        #expect(model == [])
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedDependencies()
    ) func from_outputs_a_warning_when_specific_file_not_found() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)
        try await fileSystem.makeDirectory(at: temporaryPath.appending(component: "Resources"))

        let manifest = ProjectDescription.ResourceFileElement.glob(pattern: "Resources/Image.png")
        let model = try await XcodeGraph.ResourceFileElement.from(
            manifest: manifest, generatorPaths: generatorPaths, fileSystem: fileSystem
        )

        TuistTest.expectLogs("No files found at: \(temporaryPath.appending(components: "Resources", "Image.png"))")
        #expect(model == [])
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies()) func from_when_no_files_found_in_opaque_directory() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)
        let assetsDirectory = temporaryPath.appending(components: "Resources", "Assets.xcassets")
        try await fileSystem.makeDirectory(at: assetsDirectory)

        let manifest = ProjectDescription.ResourceFileElement.glob(pattern: "Resources/Assets.xcassets/**")
        let model = try await XcodeGraph.ResourceFileElement.from(
            manifest: manifest, generatorPaths: generatorPaths, fileSystem: fileSystem
        )

        TuistTest.doesntExpectLogs("No files found at: \(assetsDirectory.appending(components: "**"))")
        #expect(model == [])
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies()) func from_when_files_found_in_opaque_directory() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)
        let assetsDirectory = temporaryPath.appending(components: "Resources", "Assets.xcassets")
        try await fileSystem.makeDirectory(at: assetsDirectory)
        try await fileSystem.touch(assetsDirectory.appending(component: "image.png"))

        let manifest = ProjectDescription.ResourceFileElement.glob(pattern: "Resources/Assets.xcassets/**")
        let model = try await XcodeGraph.ResourceFileElement.from(
            manifest: manifest, generatorPaths: generatorPaths, fileSystem: fileSystem
        )

        TuistTest.doesntExpectLogs("No files found at: \(assetsDirectory.appending(components: "**"))")
        #expect(model == [.file(path: assetsDirectory, tags: [], inclusionCondition: nil)])
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedDependencies()
    ) func from_outputs_a_warning_when_the_folder_reference_is_invalid() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)
        try await TuistTest.createFiles(["README.md"])

        let manifest = ProjectDescription.ResourceFileElement.folderReference(path: "README.md")
        let model = try await XcodeGraph.ResourceFileElement.from(
            manifest: manifest, generatorPaths: generatorPaths, fileSystem: fileSystem
        )

        TuistTest.expectLogs("README.md is not a directory - folder reference paths need to point to directories")
        #expect(model == [])
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedDependencies()
    ) func resourceFileElement_warning_withMissingFolderReference() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)
        let manifest = ProjectDescription.ResourceFileElement.folderReference(path: "Documentation")
        let model = try await XcodeGraph.ResourceFileElement.from(
            manifest: manifest, generatorPaths: generatorPaths, fileSystem: fileSystem
        )

        TuistTest.expectLogs("Documentation does not exist")
        #expect(model == [])
    }

    @Test(.inTemporaryDirectory) func from_outputs_empty_when_the_glob_is_invalid() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)
        let manifest = ProjectDescription.ResourceFileElement.glob(pattern: "invalid/path/**/*")

        let got = try await XcodeGraph.ResourceFileElement.from(
            manifest: manifest, generatorPaths: generatorPaths, fileSystem: fileSystem
        )

        #expect(got.isEmpty)
    }

    @Test(.inTemporaryDirectory) func excluding_file() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)
        let resourcesFolder = temporaryPath.appending(component: "Resources")
        let includedResource = resourcesFolder.appending(component: "included.xib")
        try await fileSystem.makeDirectory(at: resourcesFolder)
        try await fileSystem.writeText("", at: includedResource)
        try await fileSystem.writeText("", at: resourcesFolder.appending(component: "excluded.xib"))

        let manifest = ProjectDescription.ResourceFileElement.glob(pattern: "Resources/**", excluding: ["Resources/excluded.xib"])
        let got = try await XcodeGraph.ResourceFileElement.from(
            manifest: manifest, generatorPaths: generatorPaths, fileSystem: fileSystem
        )

        #expect(got == [.file(path: includedResource, tags: [])])
    }

    @Test(.inTemporaryDirectory) func excluding_folder() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)
        let resourcesFolder = temporaryPath.appending(component: "Resources")
        let excludedResourcesFolder = resourcesFolder.appending(component: "Excluded")
        let includedResource = resourcesFolder.appending(component: "included.xib")
        try await fileSystem.makeDirectory(at: resourcesFolder)
        try await fileSystem.writeText("", at: includedResource)
        try await fileSystem.writeText("", at: excludedResourcesFolder.appending(component: "excluded.xib"))

        let manifest = ProjectDescription.ResourceFileElement.glob(pattern: "Resources/**", excluding: ["Resources/Excluded"])
        let got = try await XcodeGraph.ResourceFileElement.from(
            manifest: manifest, generatorPaths: generatorPaths, fileSystem: fileSystem
        )

        #expect(got == [.file(path: includedResource, tags: [])])
    }

    @Test(.inTemporaryDirectory) func excluding_glob() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)
        let resourcesFolder = temporaryPath.appending(component: "Resources")
        let excludedResourcesFolder = resourcesFolder.appending(component: "Excluded")
        let includedResource = resourcesFolder.appending(component: "included.xib")
        try await fileSystem.makeDirectory(at: resourcesFolder)
        try await fileSystem.writeText("", at: includedResource)
        try await fileSystem.writeText("", at: excludedResourcesFolder.appending(component: "excluded.xib"))

        let manifest = ProjectDescription.ResourceFileElement.glob(pattern: "Resources/**", excluding: ["Resources/Excluded/**"])
        let got = try await XcodeGraph.ResourceFileElement.from(
            manifest: manifest, generatorPaths: generatorPaths, fileSystem: fileSystem
        )

        #expect(got == [.file(path: includedResource, tags: [])])
    }

    @Test(.inTemporaryDirectory) func excluding_when_pattern_is_file() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)
        let resourcesFolder = temporaryPath.appending(component: "Resources")
        try await fileSystem.makeDirectory(at: resourcesFolder)
        try await fileSystem.writeText("", at: resourcesFolder.appending(component: "excluded.xib"))

        let manifest = ProjectDescription.ResourceFileElement.glob(
            pattern: "Resources/excluded.xib",
            excluding: ["Resources/excluded.xib"]
        )
        let got = try await XcodeGraph.ResourceFileElement.from(
            manifest: manifest, generatorPaths: generatorPaths, fileSystem: fileSystem
        )

        #expect(got == [])
    }
}
