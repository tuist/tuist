import Foundation
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting

final class XcodeErrorTests: TuistUnitTestCase {
    func test_description() {
        XCTAssertEqual(
            XcodeError.infoPlistNotFound(.root).description,
            "Couldn't find Xcode's Info.plist at /. Make sure your Xcode installation is selected by running: sudo xcode-select -s /Applications/Xcode.app"
        )
    }

    func test_type() {
        XCTAssertEqual(XcodeError.infoPlistNotFound(.root).type, .abort)
    }
}

final class XcodeTests: TuistUnitTestCase {
    var plistEncoder: PropertyListEncoder!

    override func setUp() {
        super.setUp()
        plistEncoder = PropertyListEncoder()
    }

    override func tearDown() {
        plistEncoder = nil
        super.tearDown()
    }

    func test_read() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let infoPlist = Xcode.InfoPlist(version: "3.2.1")
        let infoPlistData = try plistEncoder.encode(infoPlist)
        let contentsPath = temporaryPath.appending(component: "Contents")
        try FileHandler.shared.createFolder(contentsPath)
        let infoPlistPath = contentsPath.appending(component: "Info.plist")
        try infoPlistData.write(to: infoPlistPath.url)

        // When
        let xcode = try Xcode.read(path: temporaryPath)

        // Then
        XCTAssertEqual(xcode.infoPlist.version, "3.2.1")
        XCTAssertEqual(xcode.path, temporaryPath)
    }

    func test_read_when_infoPlist_doesnt_exist() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let contentsPath = temporaryPath.appending(component: "Contents")
        let infoPlistPath = contentsPath.appending(component: "Info.plist")

        // When
        XCTAssertThrowsSpecific(try Xcode.read(path: temporaryPath), XcodeError.infoPlistNotFound(infoPlistPath))
    }
}
