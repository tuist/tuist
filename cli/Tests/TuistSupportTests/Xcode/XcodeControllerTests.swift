import FileSystem
import Foundation
import struct TSCUtility.Version
import XCTest

@testable import TuistSupport
@testable import TuistTesting

final class XcodeControllerTests: TuistUnitTestCase {
    var subject: XcodeController!

    override func setUp() {
        super.setUp()
        subject = XcodeController(commandRunner: mockCommandRunner)
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_selected_when_xcodeSelectDoesntReturnThePath() async throws {
        // Given
        mockCommandRunner.errorCommand(["xcode-select", "-p"])

        // When / Then
        do {
            _ = try await subject.selected()
            XCTFail("Should have failed")
        } catch {}
    }

    func test_selected_is_cached() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let contentsPath = temporaryPath.appending(component: "Contents")
        try await FileSystem().makeDirectory(at: contentsPath)
        let infoPlistPath = contentsPath.appending(component: "Info.plist")
        let developerPath = contentsPath.appending(component: "Developer")
        let infoPlist = Xcode.InfoPlist(version: "11.3")
        let infoPlistData = try PropertyListEncoder().encode(infoPlist)
        try infoPlistData.write(to: infoPlistPath.url)

        mockCommandRunner.succeedCommand(["xcode-select", "-p"], output: developerPath.pathString)

        // When
        _ = try await subject.selected()

        // Then
        // Testing that on the second run the value is cached and does not trigger a terminal command
        mockCommandRunner.errorCommand(["xcode-select", "-p"])
        let selected = try await subject.selected()
        XCTAssertNotNil(selected)
    }

    func test_selected_when_xcodeSelectReturnsThePath() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let contentsPath = temporaryPath.appending(component: "Contents")
        try await FileSystem().makeDirectory(at: contentsPath)
        let infoPlistPath = contentsPath.appending(component: "Info.plist")
        let developerPath = contentsPath.appending(component: "Developer")
        let infoPlist = Xcode.InfoPlist(version: "3.2.1")
        let infoPlistData = try PropertyListEncoder().encode(infoPlist)
        try infoPlistData.write(to: infoPlistPath.url)

        mockCommandRunner.succeedCommand(["xcode-select", "-p"], output: developerPath.pathString)

        // When
        let xcode = try await subject.selected()

        // Then
        XCTAssertNotNil(xcode)
    }

    func test_selectedVersion_when_xcodeSelectReturnsThePath() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let contentsPath = temporaryPath.appending(component: "Contents")
        try await FileSystem().makeDirectory(at: contentsPath)
        let infoPlistPath = contentsPath.appending(component: "Info.plist")
        let developerPath = contentsPath.appending(component: "Developer")
        let infoPlist = Xcode.InfoPlist(version: "11.3")
        let infoPlistData = try PropertyListEncoder().encode(infoPlist)
        try infoPlistData.write(to: infoPlistPath.url)

        mockCommandRunner.succeedCommand(["xcode-select", "-p"], output: developerPath.pathString)

        // When
        let xcodeVersion = try await subject.selectedVersion()

        // Then
        XCTAssertEqual(Version(11, 3, 0), xcodeVersion)
    }

    func test_selectedBuildVersion_readsTheProductBuildVersion() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let contentsPath = temporaryPath.appending(component: "Contents")
        try await FileSystem().makeDirectory(at: contentsPath)
        try PropertyListEncoder().encode(Xcode.InfoPlist(version: "27.1"))
            .write(to: contentsPath.appending(component: "Info.plist").url)
        let versionPlist: [String: String] = ["CFBundleShortVersionString": "27.1", "ProductBuildVersion": "27A9269"]
        try PropertyListEncoder().encode(versionPlist).write(to: contentsPath.appending(component: "version.plist").url)
        let developerPath = contentsPath.appending(component: "Developer")
        mockCommandRunner.succeedCommand(["xcode-select", "-p"], output: developerPath.pathString)

        // When
        let buildVersion = try await subject.selectedBuildVersion()

        // Then
        XCTAssertEqual(buildVersion, "27A9269")
    }

    func test_selectedBuildVersion_when_theVersionPlistIsMissing() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let contentsPath = temporaryPath.appending(component: "Contents")
        try await FileSystem().makeDirectory(at: contentsPath)
        try PropertyListEncoder().encode(Xcode.InfoPlist(version: "27.1"))
            .write(to: contentsPath.appending(component: "Info.plist").url)
        let developerPath = contentsPath.appending(component: "Developer")
        mockCommandRunner.succeedCommand(["xcode-select", "-p"], output: developerPath.pathString)

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.selectedBuildVersion(),
            XcodeError.versionPlistNotFound(contentsPath.appending(component: "version.plist"))
        )
    }
}
