import Basic
import Foundation
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistKit

final class HomebrewCommandTests: XCTestCase {
    var system: MockSystem!
    var fileHandler: MockFileHandler!

    override func setUp() {
        system = MockSystem()
        fileHandler = try! MockFileHandler()
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
        let got = try subject.isMet(system: system, projectPath: fileHandler.currentPath)
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
        let got = try subject.isMet(system: system, projectPath: fileHandler.currentPath)
        XCTAssertFalse(got)
    }

    func test_isMet() throws {
        let subject = HomebrewCommand(packages: ["swiftlint"])
        system.whichStub = { _ in "" }
        let got = try subject.isMet(system: system, projectPath: fileHandler.currentPath)
        XCTAssertTrue(got)
    }
}
