import Foundation
import SPMUtility
import XCTest

@testable import TuistCore
@testable import TuistCoreTesting

final class XcodeControllerTests: TuistUnitTestCase {
    var subject: XcodeController!

    override func setUp() {
        super.setUp()
        subject = XcodeController()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_selected_when_xcodeSelectDoesntReturnThePath() throws {
        // Given
        system.errorCommand(["xcode-select", "-p"])

        // When
        let xcode = try subject.selected()

        // Then
        XCTAssertNil(xcode)
    }

    func test_selected_when_xcodeSelectReturnsThePath() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let contentsPath = temporaryPath.appending(component: "Contents")
        try FileHandler.shared.createFolder(contentsPath)
        let infoPlistPath = contentsPath.appending(component: "Info.plist")
        let developerPath = contentsPath.appending(component: "Developer")
        let infoPlist = Xcode.InfoPlist(version: "3.2.1")
        let infoPlistData = try PropertyListEncoder().encode(infoPlist)
        try infoPlistData.write(to: infoPlistPath.url)

        system.succeedCommand(["xcode-select", "-p"], output: developerPath.pathString)

        // When
        let xcode = try subject.selected()

        // Then
        XCTAssertNotNil(xcode)
    }

    func test_selectedVersion_when_xcodeSelectDoesntReturnThePath() throws {
        // Given
        system.errorCommand(["xcode-select", "-p"])

        // Then
        XCTAssertThrowsSpecific(try subject.selectedVersion(), XcodeController.XcodeVersionError.noXcode)
    }

    func test_selectedVersion_when_xcodeSelectReturnsThePath() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let contentsPath = temporaryPath.appending(component: "Contents")
        try FileHandler.shared.createFolder(contentsPath)
        let infoPlistPath = contentsPath.appending(component: "Info.plist")
        let developerPath = contentsPath.appending(component: "Developer")
        let infoPlist = Xcode.InfoPlist(version: "11.3")
        let infoPlistData = try PropertyListEncoder().encode(infoPlist)
        try infoPlistData.write(to: infoPlistPath.url)

        system.succeedCommand(["xcode-select", "-p"], output: developerPath.pathString)

        // When
        let xcodeVersion = try subject.selectedVersion()

        // Then
        XCTAssertEqual(Version(11, 3, 0), xcodeVersion)
    }
}
