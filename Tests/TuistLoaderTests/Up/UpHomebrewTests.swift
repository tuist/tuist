import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class UpHomebrewTests: TuistUnitTestCase {
    func test_isMet_when_homebrew_is_missing() throws {
        let temporaryPath = try self.temporaryPath()
        let subject = UpHomebrew(packages: [])
        system.whichStub = { tool in
            if tool == "brew" {
                throw NSError.test()
            } else {
                return ""
            }
        }
        let got = try subject.isMet(projectPath: temporaryPath)
        XCTAssertFalse(got)
    }

    func test_isMet_when_a_package_is_missing() throws {
        let temporaryPath = try self.temporaryPath()
        let subject = UpHomebrew(packages: ["swiftlint"])
        system.whichStub = { tool in
            if tool == "brew" {
                return ""
            } else {
                throw NSError.test()
            }
        }
        system.errorCommand("/usr/local/bin/brew", "list", "swiftlint")
        let got = try subject.isMet(projectPath: temporaryPath)
        XCTAssertFalse(got)
    }

    func test_isMet() throws {
        let temporaryPath = try self.temporaryPath()
        let subject = UpHomebrew(packages: ["swiftlint"])
        system.whichStub = { tool in
            if tool == "brew" {
                return ""
            } else {
                throw NSError.test()
            }
        }
        system.succeedCommand("/usr/local/bin/brew", "list", "swiftlint")
        let got = try subject.isMet(projectPath: temporaryPath)
        XCTAssertTrue(got)
    }

    func test_meet() throws {
        let temporaryPath = try self.temporaryPath()
        let subject = UpHomebrew(packages: ["swiftlint"])

        system.whichStub = { _ in nil }
        system.errorCommand("/usr/local/bin/brew", "list", "swiftlint")
        system.succeedCommand(
            "/usr/bin/ruby",
            "-e",
            "\"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)\""
        )
        system.succeedCommand("/usr/local/bin/brew", "install", "swiftlint")

        try subject.meet(projectPath: temporaryPath)

        XCTAssertPrinterOutputContains("""
        Installing Homebrew
        Installing Homebrew package: swiftlint
        """)
    }
}
