import Foundation
import TSCBasic
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting

final class FileManagerExtrasTests: TuistUnitTestCase {
    func testSubpaths_whenNoSymbolicLinks() throws {
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
        let got = fileManager.subpathsResolvingSymbolicLinks(atPath: folderPath.pathString)
        XCTAssertEqual(got, ["File1", "Subfolder", "Subfolder/File2"])
    }

    func testSubpaths_whenSymbolicLinksToFiles() throws {
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
        let got = fileManager.subpathsResolvingSymbolicLinks(atPath: folderPath.pathString)
        XCTAssertEqual(got, ["Subfolder", "Subfolder/File", "Symlink"])
    }

    func testSubpaths_whenSymbolicLinksToDirectory() throws {
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
        let got = fileManager.subpathsResolvingSymbolicLinks(atPath: folderPath.pathString)
        XCTAssertEqual(got, ["SymlinkFolder", "SymlinkFolder/File"])
    }

    func testSubpaths_whenSymbolicLinkAndOriginalInSameSubtree() throws {
        // Given
        let fileManager = FileManager.default

        // When

        // - <Root>
        //   - Folder
        //     - File
        //     - Symlink -> File

        let rootPath = try temporaryPath()
        let folderPath = rootPath.appending(component: "Folder")
        let filePath = folderPath.appending(component: "File")
        let symlinkPath = folderPath.appending(component: "Symlink")

        try fileHandler.createFolder(folderPath)
        try fileHandler.write("Test", path: filePath, atomically: true)
        try fileHandler.createSymbolicLink(at: symlinkPath, destination: filePath)

        // Then
        let got = fileManager.subpathsResolvingSymbolicLinks(atPath: folderPath.pathString)
        XCTAssertEqual(got, ["File", "Symlink"])
    }

    func testSubpaths_whenNestedDirectories() throws {
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
        let got = fileManager.subpathsResolvingSymbolicLinks(atPath: rootPath.pathString)
        let expected = [
            "Folder",
            "Folder/File",
            "Folder/SubFolder",
            "Folder/SubFolder/SubFile",
            "Folder/SubFolder/SubSubFolder",
            "Folder/SubFolder/SubSubFolder/SubSubFile",
        ]
        XCTAssertEqual(got, expected)
    }
}
