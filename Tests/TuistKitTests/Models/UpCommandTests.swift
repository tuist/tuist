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

final class HomebrewCommandTests: XCTestCase {
    var system: MockSystem!

    override func setUp() {
        system = MockSystem()
        super.setUp()
    }

    func test_isMet_when_homebrew_is_missing() throws {
        let subject = HomebrewCommand(packages: [])
        system.whichStub = { tool in
            if tool == "brew" {
                throw NSError.test()
            } else {
                return ""
            }
        }
        let got = try subject.isMet(system: system)
        XCTAssertFalse(got)
    }

    func test_isMet_when_a_package_is_missing() throws {
        let subject = HomebrewCommand(packages: ["swiftlint"])
        system.whichStub = { tool in
            if tool == "swiftlint" {
                throw NSError.test()
            } else {
                return ""
            }
        }
        let got = try subject.isMet(system: system)
        XCTAssertFalse(got)
    }

    func test_isMet() throws {
        let subject = HomebrewCommand(packages: ["swiftlint"])
        system.whichStub = { _ in "" }
        let got = try subject.isMet(system: system)
        XCTAssertTrue(got)
    }
}
