import Basic
import Foundation
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistKit

final class UpHomebrewTests: TuistUnitTestCase {
    func test_isMet_when_homebrew_is_missing() throws {
        let subject = UpHomebrew(packages: [])
        system.whichStub = { tool in
            if tool == "brew" {
                throw NSError.test()
            } else {
                return ""
            }
        }
        let got = try subject.isMet(projectPath: fileHandler.currentPath)
        XCTAssertFalse(got)
    }

    func test_isMet_when_a_package_is_missing() throws {
        let subject = UpHomebrew(packages: ["swiftlint"])
        system.whichStub = { tool in
            if tool == "swiftlint" {
                throw NSError.test()
            } else {
                return ""
            }
        }
        let got = try subject.isMet(projectPath: fileHandler.currentPath)
        XCTAssertFalse(got)
    }

    func test_isMet() throws {
        let subject = UpHomebrew(packages: ["swiftlint"])
        system.whichStub = { _ in "" }
        let got = try subject.isMet(projectPath: fileHandler.currentPath)
        XCTAssertTrue(got)
    }

    func test_meet() throws {
        let subject = UpHomebrew(packages: ["swiftlint"])

        system.whichStub = { _ in nil }
        system.succeedCommand("/usr/bin/ruby",
                              "-e",
                              "\"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)\"")
        system.succeedCommand("/usr/local/bin/brew", "install", "swiftlint")

        try subject.meet(projectPath: fileHandler.currentPath)

        XCTAssertPrinterOutputContains("""
        Installing Homebrew
        Installing Homebrew package: swiftlint
        """)
    }
}
