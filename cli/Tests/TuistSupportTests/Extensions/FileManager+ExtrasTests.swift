import FileSystem
import Foundation
import XCTest

@testable import TuistSupport
@testable import TuistTesting

final class FileManagerExtrasTests: TuistUnitTestCase {
    func testSubdirectoriesResolvingSymbolicLinks_whenNoSymbolicLinks() async throws {
        // Given
        let fileManager = FileManager.default

        // When

        // - <Root>
        //   - Folder
        //     - File1
        //     - Subfolder
        //       - File2

        let rootPath = try temporaryPath()
        let folderPath = rootPath.appending(component: "Folder")
        let file1Path = folderPath.appending(component: "File1")
        let subfolderPath = folderPath.appending(component: "Subfolder")
        let file2Path = subfolderPath.appending(component: "File2")
        try await fileSystem.makeDirectory(at: subfolderPath)
        try await fileSystem.writeText("Test", at: file1Path)
        try await fileSystem.writeText("Test", at: file2Path)

        // Then
        let got = fileManager.subdirectoriesResolvingSymbolicLinks(atPath: folderPath.pathString)
        XCTAssertEqual(got.sorted(), ["Subfolder"])
    }

    func testSubdirectoriesResolvingSymbolicLinks_whenSymbolicLinksToFiles() async throws {
        // Given
        let fileManager = FileManager.default

        // When

        // - <Root>
        //   - OutsideFile
        //   - Folder
        //     - Symlink -> OutsideFile
        //     - Subfolder
        //       - File

        let rootPath = try temporaryPath()
        let outsideFile = rootPath.appending(component: "OutsideFile")
        let folderPath = rootPath.appending(component: "Folder")
        let symlinkPath = folderPath.appending(component: "Symlink")
        let subfolderPath = folderPath.appending(component: "Subfolder")
        let filePath = subfolderPath.appending(component: "File")

        try await fileSystem.makeDirectory(at: subfolderPath)
        try await fileSystem.writeText("Test", at: outsideFile)
        try await fileSystem.writeText("Test", at: filePath)
        try await fileSystem.createSymbolicLink(from: symlinkPath, to: outsideFile)

        // Then
        let got = fileManager.subdirectoriesResolvingSymbolicLinks(atPath: folderPath.pathString)
        XCTAssertEqual(got.sorted(), ["Subfolder"])
    }

    func testSubdirectoriesResolvingSymbolicLinks_whenSymbolicLinksToDirectory() async throws {
        // Given
        let fileManager = FileManager.default

        // When

        // - <Root>
        //   - OutsideFolder
        //     - File
        //   - Folder
        //     - SymlinkFolder -> OutsideFolder

        let rootPath = try temporaryPath()
        let outsideFolderPath = rootPath.appending(component: "OutsideFolder")
        let filePath = outsideFolderPath.appending(component: "File")
        let folderPath = rootPath.appending(component: "Folder")
        let symlinkPath = folderPath.appending(component: "SymlinkFolder")

        try await fileSystem.makeDirectory(at: outsideFolderPath)
        try await fileSystem.makeDirectory(at: folderPath)
        try await fileSystem.writeText("Test", at: filePath)
        try await fileSystem.createSymbolicLink(from: symlinkPath, to: outsideFolderPath)

        // Then
        let got = fileManager.subdirectoriesResolvingSymbolicLinks(atPath: folderPath.pathString)
        XCTAssertEqual(got.sorted(), ["SymlinkFolder"])
    }

    func testSubdirectoriesResolvingSymbolicLinks_whenSymbolicLinkAndOriginalInSameSubtree() async throws {
        // Given
        let fileManager = FileManager.default

        // When

        // - <Root>
        //   - Folder
        //     - Subfolder
        //     - SymlinkFolder -> Subfolder

        let rootPath = try temporaryPath()
        let folderPath = rootPath.appending(component: "Folder")
        let subfolderPath = folderPath.appending(component: "Subfolder")
        let symlinkFolderPath = folderPath.appending(component: "SymlinkFolder")

        try await fileSystem.makeDirectory(at: folderPath)
        try await fileSystem.makeDirectory(at: subfolderPath)
        try await fileSystem.createSymbolicLink(from: symlinkFolderPath, to: subfolderPath)

        // Then
        let got = fileManager.subdirectoriesResolvingSymbolicLinks(atPath: folderPath.pathString)
        XCTAssertEqual(got.sorted(), ["Subfolder", "SymlinkFolder"])
    }

    func testSubdirectoriesResolvingSymbolicLinks_whenNestedDirectories() async throws {
        // Given
        let fileManager = FileManager.default

        // When

        // - <Root>
        //   - Folder
        //     - File
        //     - Subfolder
        //       - SubFile
        //       - SubSubfolder
        //         - SubSubFile

        let rootPath = try temporaryPath()
        let folderPath = rootPath.appending(component: "Folder")
        let filePath = folderPath.appending(component: "File")
        let subFolderPath = folderPath.appending(component: "SubFolder")
        let subFilePath = subFolderPath.appending(component: "SubFile")
        let subSubFolderPath = subFolderPath.appending(component: "SubSubFolder")
        let subSubFilePath = subSubFolderPath.appending(component: "SubSubFile")

        try await fileSystem.makeDirectory(at: folderPath)
        try await fileSystem.makeDirectory(at: subFolderPath)
        try await fileSystem.makeDirectory(at: subSubFolderPath)
        try await fileSystem.writeText("Test", at: filePath)
        try await fileSystem.writeText("Test", at: subFilePath)
        try await fileSystem.writeText("Test", at: subSubFilePath)

        // Then
        let got = fileManager.subdirectoriesResolvingSymbolicLinks(atPath: rootPath.pathString)
        let expected = [
            "Folder",
            "Folder/SubFolder",
            "Folder/SubFolder/SubSubFolder",
        ]
        XCTAssertEqual(got.sorted(), expected)
    }

    func testSubdirectoriesResolvingSymbolicLinks_whenNestedSymlinks() async throws {
        // Given
        let fileManager = FileManager.default

        // When

        // - <Root>
        //   - OtherOutsideFolder
        //     - Subfolder
        //   - OutsideFolder
        //     - SubSymlinkFolder -> OtherOutsideFolder
        //   - Folder
        //     - SymlinkFolder -> OutsideFolder

        let rootPath = try temporaryPath()
        let otherOutsideFolderPath = rootPath.appending(component: "OtherOutsideFolder")
        let subFolderPath = otherOutsideFolderPath.appending(component: "Subfolder")
        let outsideFolderPath = rootPath.appending(component: "OutsideFolder")
        let subSymlinkFolderPath = outsideFolderPath.appending(component: "SubSymlinkFolder")
        let folderPath = rootPath.appending(component: "Folder")
        let symlinkFolderPath = folderPath.appending(component: "SymlinkFolder")

        try await fileSystem.makeDirectory(at: folderPath)
        try await fileSystem.makeDirectory(at: outsideFolderPath)
        try await fileSystem.makeDirectory(at: otherOutsideFolderPath)
        try await fileSystem.makeDirectory(at: subFolderPath)
        try await fileSystem.createSymbolicLink(from: symlinkFolderPath, to: outsideFolderPath)
        try await fileSystem.createSymbolicLink(from: subSymlinkFolderPath, to: otherOutsideFolderPath)

        // Then
        let got = fileManager.subdirectoriesResolvingSymbolicLinks(atPath: folderPath.pathString)
        let expected = [
            "SymlinkFolder",
            "SymlinkFolder/SubSymlinkFolder",
            "SymlinkFolder/SubSymlinkFolder/Subfolder",
        ]
        XCTAssertEqual(got.sorted(), expected)
    }

    func testSubdirectoriesResolvingSymbolicLinks_whenRelativeSymlink() async throws {
        // Given
        let fileManager = FileManager.default

        // When

        // - <Root>
        //   - OutsideFolder
        //     - Subfolder
        //   - Folder
        //     - SymlinkFolder -> [Relative] OutsideFolder

        let rootPath = try temporaryPath()
        let outsideFolderPath = rootPath.appending(component: "OutsideFolder")
        let subfolderPath = outsideFolderPath.appending(component: "Subfolder")
        let folderPath = rootPath.appending(component: "Folder")
        let symlinkFolderPath = folderPath.appending(component: "SymlinkFolder")

        try await fileSystem.makeDirectory(at: folderPath)
        try await fileSystem.makeDirectory(at: outsideFolderPath)
        try await fileSystem.makeDirectory(at: subfolderPath)
        try fileManager.createSymbolicLink(atPath: symlinkFolderPath.pathString, withDestinationPath: "../OutsideFolder")

        // Then
        let got = fileManager.subdirectoriesResolvingSymbolicLinks(atPath: folderPath.pathString)
        let expected = [
            "SymlinkFolder",
            "SymlinkFolder/Subfolder",
        ]
        XCTAssertEqual(got.sorted(), expected)
    }
}
