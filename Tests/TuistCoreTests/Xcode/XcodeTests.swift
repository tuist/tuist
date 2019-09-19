import Foundation
import XCTest

@testable import TuistCore
@testable import TuistCoreTesting

final class XcodeTests: XCTestCase {
    var plistEncoder: PropertyListEncoder!
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()
        mockAllSystemInteractions()
        fileHandler = sharedMockFileHandler()

        plistEncoder = PropertyListEncoder()
    }

    func test_read() throws {
        // Given
        let infoPlist = Xcode.InfoPlist(version: "3.2.1")
        let infoPlistData = try plistEncoder.encode(infoPlist)
        let contentsPath = fileHandler.currentPath.appending(component: "Contents")
        try fileHandler.createFolder(contentsPath)
        let infoPlistPath = contentsPath.appending(component: "Info.plist")
        try infoPlistData.write(to: infoPlistPath.url)

        // When
        let xcode = try Xcode.read(path: fileHandler.currentPath)

        // Then
        XCTAssertEqual(xcode.infoPlist.version, "3.2.1")
        XCTAssertEqual(xcode.path, fileHandler.currentPath)
    }
}
