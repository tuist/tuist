import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
@testable import TuistSupport
@testable import TuistTesting

struct FileHandlerErrorTests {
    @Test
    func test_description() {
        #expect(FileHandlerError.invalidTextEncoding(try AbsolutePath(validating: "/path"))
            .description == "The file at /path is not a utf8 text file")
        #expect(FileHandlerError.writingError(try AbsolutePath(validating: "/path"))
            .description == "Couldn't write to the file /path")
    }
}

struct FileHandlerTests {
    struct TestDecodable: Decodable {}

    private let subject: FileHandler
    private let fileManager = FileManager.default

    // MARK: - Setup

    init() {
        subject = FileHandler()
    }

    // MARK: - Tests

    @Test(.inTemporaryDirectory)
    func test_replace() throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let tempFile = temporaryPath.appending(component: "Temporary")
        let destFile = temporaryPath.appending(component: "Destination")
        try "content".write(to: URL(fileURLWithPath: tempFile.pathString), atomically: true, encoding: .utf8)

        // When
        try subject.replace(destFile, with: tempFile)

        // Then
        let content = try String(contentsOf: URL(fileURLWithPath: destFile.pathString))
        #expect(content == "content")
    }

    @Test
    func decode() throws {
        let testPlistPath = SwiftTestingHelper.fixturePath(path: try RelativePath(validating: "Test.plist"))
        let xcframeworkInfoPlist: TestPlist = try subject.readPlistFile(testPlistPath)
        #expect(xcframeworkInfoPlist != nil)
    }

    @Test(.inTemporaryDirectory)
    func replace_cleans_up_temp() throws {
        // FIX: This test runs fine locally but it fails on CI.
        // // Given
        // let temporaryPath = try self.try #require(FileSystem.temporaryTestDirectory)
        // let from = temporaryPath.appending(component: "from")
        // try FileHandler.shared.touch(from)
        // let to = temporaryPath.appending(component: "to")

        // let count = try countItemsInRootTempDirectory(appropriateFor: to.asURL)

        // // When
        // try subject.replace(to, with: from)

        // // Then
        // #expect(count == try countItemsInRootTempDirectory(appropriateFor: to.asURL))
    }

    @Test
    func base64MD5() throws {
        // Given
        let testZippedFrameworkPath = SwiftTestingHelper.fixturePath(path: try RelativePath(validating: "uUI.xcframework.zip"))

        // When
        let result = try subject.urlSafeBase64MD5(path: testZippedFrameworkPath)

        // Then
        #expect(result == "X0vsGS0PGIT9z0l1s3Bn3A==")
    }

    @Test(.inTemporaryDirectory)
    func readPlistFile_throwsAnError_when_invalidPlist() throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let plistPath = temporaryDirectory.appending(component: "file.plist")
        try FileHandler.shared.touch(plistPath)

        // When/Then
        var _error: Error? = nil
        do {
            let _: TestDecodable = try subject.readPlistFile<TestDecodable>(plistPath)
        } catch {
            _error = error
        }
        #expect(_error as? FileHandlerError == FileHandlerError.propertyListDecodeError(
            plistPath,
            description: "The given data was not a valid property list."
        ))
    }

    // MARK: - Private

    private func countItemsInRootTempDirectory(appropriateFor url: URL) throws -> Int {
        let tempPath = try AbsolutePath(validating: try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: url,
            create: true
        ).path)
        let rootTempPath = tempPath.parentDirectory
        try fileManager.removeItem(at: URL(fileURLWithPath: tempPath.pathString))
        let content = try fileManager.contentsOfDirectory(atPath: rootTempPath.pathString)
        return content.count
    }
}

private struct TestPlist: Decodable {
    enum CodingKeys: CodingKey {
        case platforms
    }

    struct Platform: Decodable {
        enum CodingKeys: CodingKey {
            case name
            case supportedLanguages
        }

        let name: String
        let supportedLanguages: [String]
    }

    let platforms: [Platform]
}
