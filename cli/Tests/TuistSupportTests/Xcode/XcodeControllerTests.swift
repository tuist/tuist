import Foundation
import struct TSCUtility.Version
import FileSystemTesting
import Testing

@testable import TuistSupport
@testable import TuistTesting

struct XcodeControllerTests {
    let subject: XcodeController
    init() {
        subject = XcodeController()
    }


    @Test
    func test_selected_when_xcodeSelectDoesntReturnThePath() async throws {
        // Given
        system.errorCommand(["xcode-select", "-p"])

        // When / Then
        do {
            _ = try await subject.selected()
            Issue.record("Should have failed")
        } catch {}
    }

    @Test(.inTemporaryDirectory)
    func test_selected_is_cached() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let contentsPath = temporaryPath.appending(component: "Contents")
        try FileHandler.shared.createFolder(contentsPath)
        let infoPlistPath = contentsPath.appending(component: "Info.plist")
        let developerPath = contentsPath.appending(component: "Developer")
        let infoPlist = Xcode.InfoPlist(version: "11.3")
        let infoPlistData = try PropertyListEncoder().encode(infoPlist)
        try infoPlistData.write(to: infoPlistPath.url)

        system.succeedCommand(["xcode-select", "-p"], output: developerPath.pathString)

        // When
        _ = try await subject.selected()

        // Then
        // Testing that on the second run the value is cached and does not trigger a terminal command
        system.errorCommand(["xcode-select", "-p"])
        let selected = try await subject.selected()
        #expect(selected != nil)
    }

    @Test(.inTemporaryDirectory)
    func test_selected_when_xcodeSelectReturnsThePath() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let contentsPath = temporaryPath.appending(component: "Contents")
        try FileHandler.shared.createFolder(contentsPath)
        let infoPlistPath = contentsPath.appending(component: "Info.plist")
        let developerPath = contentsPath.appending(component: "Developer")
        let infoPlist = Xcode.InfoPlist(version: "3.2.1")
        let infoPlistData = try PropertyListEncoder().encode(infoPlist)
        try infoPlistData.write(to: infoPlistPath.url)

        system.succeedCommand(["xcode-select", "-p"], output: developerPath.pathString)

        // When
        let xcode = try await subject.selected()

        // Then
        #expect(xcode != nil)
    }

    @Test(.inTemporaryDirectory)
    func test_selectedVersion_when_xcodeSelectReturnsThePath() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let contentsPath = temporaryPath.appending(component: "Contents")
        try FileHandler.shared.createFolder(contentsPath)
        let infoPlistPath = contentsPath.appending(component: "Info.plist")
        let developerPath = contentsPath.appending(component: "Developer")
        let infoPlist = Xcode.InfoPlist(version: "11.3")
        let infoPlistData = try PropertyListEncoder().encode(infoPlist)
        try infoPlistData.write(to: infoPlistPath.url)

        system.succeedCommand(["xcode-select", "-p"], output: developerPath.pathString)

        // When
        let xcodeVersion = try await subject.selectedVersion()

        // Then
        #expect(Version(11, 3, 0) == xcodeVersion)
    }
}
