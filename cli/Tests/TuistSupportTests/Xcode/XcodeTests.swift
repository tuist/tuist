import Foundation
import FileSystemTesting
import Testing

@testable import TuistSupport
@testable import TuistTesting

struct XcodeErrorTests {
    @Test
    func test_description() {
        #expect(XcodeError.infoPlistNotFound(.root).description == "Couldn't find Xcode's Info.plist at /. Make sure your Xcode installation is selected by running: sudo xcode-select -s /Applications/Xcode.app")
    }

    @Test
    func test_type() {
        #expect(XcodeError.infoPlistNotFound(.root).type == .abort)
    }
}

struct XcodeTests {
    let plistEncoder: PropertyListEncoder
    init() {
        plistEncoder = PropertyListEncoder()
    }


    @Test(.inTemporaryDirectory)
    func test_read() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let infoPlist = Xcode.InfoPlist(version: "3.2.1")
        let infoPlistData = try plistEncoder.encode(infoPlist)
        let contentsPath = temporaryPath.appending(component: "Contents")
        try FileHandler.shared.createFolder(contentsPath)
        let infoPlistPath = contentsPath.appending(component: "Info.plist")
        try infoPlistData.write(to: infoPlistPath.url)

        // When
        let xcode = try await Xcode.read(path: temporaryPath)

        // Then
        #expect(xcode.infoPlist.version == "3.2.1")
        #expect(xcode.path == temporaryPath)
    }

    @Test(.inTemporaryDirectory)
    func test_read_when_infoPlist_doesnt_exist() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let contentsPath = temporaryPath.appending(component: "Contents")
        let infoPlistPath = contentsPath.appending(component: "Info.plist")

        // When
        await #expect(throws: XcodeError.infoPlistNotFound(infoPlistPath)) { try await Xcode.read(path: temporaryPath) }
    }
}
