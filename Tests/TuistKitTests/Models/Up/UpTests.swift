import Basic
import Foundation
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistKit

final class UpTests: XCTestCase {
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()
        mockAllSystemInteractions()
        fileHandler = sharedMockFileHandler()
    }

    func test_with_when_custom() throws {
        let dictionary = JSON([
            "type": "custom",
            "name": "name",
            "is_met": JSON.array([JSON.string("is_met")]),
            "meet": JSON.array([JSON.string("meet")]),
        ])
        let got = try Up.with(dictionary: dictionary,
                              projectPath: fileHandler.currentPath) as? UpCustom
        XCTAssertEqual(got?.name, "name")
        XCTAssertEqual(got?.meet, ["meet"])
        XCTAssertEqual(got?.isMet, ["is_met"])
    }

    func test_with_when_homebrew() throws {
        let dictionary = JSON([
            "type": "homebrew",
            "packages": JSON.array([JSON.string("swiftlint")]),
        ])
        let got = try Up.with(dictionary: dictionary,
                              projectPath: fileHandler.currentPath) as? UpHomebrew
        XCTAssertEqual(got?.name, "Homebrew")
        XCTAssertEqual(got?.packages, ["swiftlint"])
    }

    func test_with_when_homebrewTap() throws {
        let dictionary = JSON([
            "type": "homebrew-tap",
            "repositories": JSON.array([JSON.string("repository")]),
        ])
        let got = try Up.with(dictionary: dictionary,
                              projectPath: fileHandler.currentPath) as? UpHomebrewTap
        XCTAssertEqual(got?.name, "Homebrew tap")
        XCTAssertEqual(got?.repositories, ["repository"])
    }

    func test_with_when_carthage() throws {
        let dictionary = JSON([
            "type": "carthage",
            "platforms": JSON.array([JSON.string("macos")]),
        ])
        let got = try Up.with(dictionary: dictionary,
                              projectPath: fileHandler.currentPath) as? UpCarthage
        XCTAssertEqual(got?.name, "Carthage update")
        XCTAssertEqual(got?.platforms, [.macOS])
    }
}
