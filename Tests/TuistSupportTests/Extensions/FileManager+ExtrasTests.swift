import Foundation
import TSCBasic
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting

final class FileManagerExtrasTests: TuistUnitTestCase {
    func testSubdirectoriesResolvingSymbolicLinks_whenNoSymbolicLinks() throws {
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
        try fileHandler.createFolder(subfolderPath)
        try fileHandler.write("Test", path: file1Path, atomically: true)
        try fileHandler.write("Test", path: file2Path, atomically: true)

        // Then
        let got = fileManager.subdirectoriesResolvingSymbolicLinks(atPath: folderPath.pathString)
        XCTAssertEqual(got.sorted(), ["Subfolder"])
    }

    func testSubdirectoriesResolvingSymbolicLinks_whenSymbolicLinksToFiles() throws {
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

        try fileHandler.createFolder(subfolderPath)
        try fileHandler.write("Test", path: outsideFile, atomically: true)
        try fileHandler.write("Test", path: filePath, atomically: true)
        try fileHandler.createSymbolicLink(at: symlinkPath, destination: outsideFile)

        // Then
        let got = fileManager.subdirectoriesResolvingSymbolicLinks(atPath: folderPath.pathString)
        XCTAssertEqual(got.sorted(), ["Subfolder"])
    }

    func testSubdirectoriesResolvingSymbolicLinks_whenSymbolicLinksToDirectory() throws {
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

        try fileHandler.createFolder(outsideFolderPath)
        try fileHandler.createFolder(folderPath)
        try fileHandler.write("Test", path: filePath, atomically: true)
        try fileHandler.createSymbolicLink(at: symlinkPath, destination: outsideFolderPath)

        // Then
        let got = fileManager.subdirectoriesResolvingSymbolicLinks(atPath: folderPath.pathString)
        XCTAssertEqual(got.sorted(), ["SymlinkFolder"])
    }

    func testSubdirectoriesResolvingSymbolicLinks_whenSymbolicLinkAndOriginalInSameSubtree() throws {
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

        try fileHandler.createFolder(folderPath)
        try fileHandler.createFolder(subfolderPath)
        try fileHandler.createSymbolicLink(at: symlinkFolderPath, destination: subfolderPath)

        // Then
        let got = fileManager.subdirectoriesResolvingSymbolicLinks(atPath: folderPath.pathString)
        XCTAssertEqual(got.sorted(), ["Subfolder", "SymlinkFolder"])
    }

    func testSubdirectoriesResolvingSymbolicLinks_whenNestedDirectories() throws {
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

        try fileHandler.createFolder(folderPath)
        try fileHandler.createFolder(subFolderPath)
        try fileHandler.createFolder(subSubFolderPath)
        try fileHandler.write("Test", path: filePath, atomically: true)
        try fileHandler.write("Test", path: subFilePath, atomically: true)
        try fileHandler.write("Test", path: subSubFilePath, atomically: true)

        // Then
        let got = fileManager.subdirectoriesResolvingSymbolicLinks(atPath: rootPath.pathString)
        let expected = [
            "Folder",
            "Folder/SubFolder",
            "Folder/SubFolder/SubSubFolder",
        ]
        XCTAssertEqual(got.sorted(), expected)
    }

    func testSubdirectoriesResolvingSymbolicLinks_whenNestedSymlinks() throws {
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

        try fileHandler.createFolder(folderPath)
        try fileHandler.createFolder(outsideFolderPath)
        try fileHandler.createFolder(otherOutsideFolderPath)
        try fileHandler.createFolder(subFolderPath)
        try fileHandler.createSymbolicLink(at: symlinkFolderPath, destination: outsideFolderPath)
        try fileHandler.createSymbolicLink(at: subSymlinkFolderPath, destination: otherOutsideFolderPath)

        // Then
        let got = fileManager.subdirectoriesResolvingSymbolicLinks(atPath: folderPath.pathString)
        let expected = [
            "SymlinkFolder",
            "SymlinkFolder/SubSymlinkFolder",
            "SymlinkFolder/SubSymlinkFolder/Subfolder",
        ]
        XCTAssertEqual(got.sorted(), expected)
    }

    func testSubdirectoriesResolvingSymbolicLinks_whenRelativeSymlink() throws {
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

        try fileHandler.createFolder(folderPath)
        try fileHandler.createFolder(outsideFolderPath)
        try fileHandler.createFolder(subfolderPath)
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
