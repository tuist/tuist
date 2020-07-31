import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class UpTests: TuistUnitTestCase {
    func test_with_when_custom() throws {
        let temporaryPath = try self.temporaryPath()
        let dictionary = JSON([
            "type": "custom",
            "name": "name",
            "is_met": JSON.array([JSON.string("is_met")]),
            "meet": JSON.array([JSON.string("meet")]),
        ])
        let got = try Up.with(dictionary: dictionary, projectPath: temporaryPath) as? UpCustom
        XCTAssertEqual(got?.name, "name")
        XCTAssertEqual(got?.meet, ["meet"])
        XCTAssertEqual(got?.isMet, ["is_met"])
    }

    func test_with_when_homebrew() throws {
        let temporaryPath = try self.temporaryPath()
        let dictionary = JSON([
            "type": "homebrew",
            "packages": JSON.array([JSON.string("swiftlint")]),
        ])
        let got = try Up.with(dictionary: dictionary, projectPath: temporaryPath) as? UpHomebrew
        XCTAssertEqual(got?.name, "Homebrew")
        XCTAssertEqual(got?.packages, ["swiftlint"])
    }

    func test_with_when_homebrewTap() throws {
        let temporaryPath = try self.temporaryPath()
        let dictionary = JSON([
            "type": "homebrew-tap",
            "repositories": JSON.array([JSON.string("repository")]),
        ])
        let got = try Up.with(dictionary: dictionary, projectPath: temporaryPath) as? UpHomebrewTap
        XCTAssertEqual(got?.name, "Homebrew tap")
        XCTAssertEqual(got?.repositories, ["repository"])
    }

    func test_with_when_homebrewCask() throws {
        let temporaryPath = try self.temporaryPath()
        let dictionary = JSON([
            "type": "homebrew-cask",
            "projects": JSON.array([JSON.string("project")]),
        ])
        let got = try Up.with(dictionary: dictionary, projectPath: temporaryPath) as? UpHomebrewCask
        XCTAssertEqual(got?.name, "Homebrew cask")
        XCTAssertEqual(got?.projects, ["project"])
    }

    func test_with_when_carthage() throws {
        let temporaryPath = try self.temporaryPath()
        let dictionary = JSON([
            "type": "carthage",
            "platforms": JSON.array([JSON.string("macos")]),
        ])
        let got = try Up.with(dictionary: dictionary, projectPath: temporaryPath) as? UpCarthage
        XCTAssertEqual(got?.name, "Carthage update")
        XCTAssertEqual(got?.platforms, [.macOS])
    }

    func test_with_when_mint() throws {
        let temporaryPath = try self.temporaryPath()
        let dictionary = JSON([
            "type": "mint",
            "linkPackagesGlobally": JSON.bool(true),
        ])
        let got = try Up.with(dictionary: dictionary, projectPath: temporaryPath) as? UpMint
        XCTAssertEqual(got?.name, "Mint")
        XCTAssertEqual(got?.linkPackagesGlobally, true)
    }
}
