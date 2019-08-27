import Foundation
import XCTest

@testable import TuistCore
@testable import TuistCoreTesting

final class XcodeControllerTests: XCTestCase {
    var system: MockSystem!
    var subject: XcodeController!
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()
        mockEnvironment()
        fileHandler = sharedMockFileHandler()

        system = MockSystem()
        subject = XcodeController(system: system)
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
        let contentsPath = fileHandler.currentPath.appending(component: "Contents")
        try fileHandler.createFolder(contentsPath)
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
}
