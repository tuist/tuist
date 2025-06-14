import Foundation
import struct TSCUtility.Version
import XCTest

@testable import TuistSupport
@testable import TuistTesting

final class XcodeControllerTests: TuistUnitTestCase {
    var subject: XcodeController!

    override func setUp() {
        super.setUp()
        subject = XcodeController()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_selected_when_xcodeSelectDoesntReturnThePath() async throws {
        // Given
        system.errorCommand(["xcode-select", "-p"])

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
        XCTAssertNotNil(selected)
    }

    func test_selected_when_xcodeSelectReturnsThePath() async throws {
        // Given
        let temporaryPath = try temporaryPath()
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
        XCTAssertNotNil(xcode)
    }

    func test_selectedVersion_when_xcodeSelectReturnsThePath() async throws {
        // Given
        let temporaryPath = try temporaryPath()
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
        XCTAssertEqual(Version(11, 3, 0), xcodeVersion)
    }
}
