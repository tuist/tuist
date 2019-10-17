import Foundation
import XCTest

@testable import TuistCore
@testable import TuistCoreTesting

final class XcodeTests: TuistUnitTestCase {
    var plistEncoder: PropertyListEncoder!

    override func setUp() {
        super.setUp()
        plistEncoder = PropertyListEncoder()
    }

    override func tearDown() {
        super.tearDown()
        plistEncoder = nil
    }

    func test_read() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
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
}
