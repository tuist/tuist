import Basic
import Foundation
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistKit

final class UpCommandTests: XCTestCase {
    var fileHandler: MockFileHandler!

    override func setUp() {
        fileHandler = try! MockFileHandler()
        super.setUp()
    }

    func test_with_when_custom() throws {
        let dictionary = JSON([
            "type": "custom",
            "name": "name",
            "is_met": JSON.array([JSON.string("is_met")]),
            "meet": JSON.array([JSON.string("meet")]),
        ])
        let got = try UpCommand.with(dictionary: dictionary,
                                     projectPath: fileHandler.currentPath,
                                     fileHandler: fileHandler) as? CustomCommand
        XCTAssertEqual(got?.name, "name")
        XCTAssertEqual(got?.meet, ["meet"])
        XCTAssertEqual(got?.isMet, ["is_met"])
    }

    func test_with_when_homebrew() throws {
        let dictionary = JSON([
            "type": "homebrew",
            "packages": JSON.array([JSON.string("swiftlint")]),
        ])
        let got = try UpCommand.with(dictionary: dictionary,
                                     projectPath: fileHandler.currentPath,
                                     fileHandler: fileHandler) as? HomebrewCommand
        XCTAssertEqual(got?.name, "Homebrew")
        XCTAssertEqual(got?.packages, ["swiftlint"])
    }
}
