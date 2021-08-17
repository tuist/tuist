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
        XCTAssertEqual(got, [file1Path, subfolderPath, file2Path].map(\.pathString))
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
        XCTAssertEqual(got, [subfolderPath, filePath, symlinkPath].map(\.pathString))
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
        XCTAssertEqual(got, [symlinkPath, symlinkPath.appending(component: "File")].map(\.pathString))
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
        XCTAssertEqual(got, [filePath, symlinkPath].map(\.pathString))
    }
}
