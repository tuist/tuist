import Basic
import Foundation
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistKit

final class UpHomebrewTapTests: XCTestCase {
    var system: MockSystem!
    var fileHandler: MockFileHandler!
    var upHomebrew: MockUp!

    override func setUp() {
        super.setUp()
        mockAllSystemInteractions()
        fileHandler = sharedMockFileHandler()

        system = MockSystem()
        upHomebrew = MockUp()
    }

    func test_isMet_when_homebrewIsNotMet() throws {
        // Given
        let subject = UpHomebrewTap(repositories: [], upHomebrew: upHomebrew)
        upHomebrew.isMetStub = { _, _ in false }

        // When
        let got = try subject.isMet(system: system, projectPath: fileHandler.currentPath)

        // Then
        XCTAssertFalse(got)
    }

    func test_isMet_when_tapsAreMissing() throws {
        // Given
        let subject = UpHomebrewTap(repositories: ["repo"], upHomebrew: upHomebrew)
        upHomebrew.isMetStub = { _, _ in true }
        system.succeedCommand(["brew", "tap"], output: "")

        // When
        let got = try subject.isMet(system: system, projectPath: fileHandler.currentPath)

        // Then
        XCTAssertFalse(got)
    }

    func test_isMet_when_allTapsAreConfigured() throws {
        // Given
        let subject = UpHomebrewTap(repositories: ["repo"], upHomebrew: upHomebrew)
        upHomebrew.isMetStub = { _, _ in true }
        system.succeedCommand(["brew", "tap"], output: "repo\nother\n")

        // When
        let got = try subject.isMet(system: system, projectPath: fileHandler.currentPath)

        // Then
        XCTAssertTrue(got)
    }

    func test_meet() throws {
        // When
        let subject = UpHomebrewTap(repositories: ["repo"], upHomebrew: upHomebrew)
        system.succeedCommand(["brew", "tap"], output: "")
        system.succeedCommand(["brew", "tap", "repo"])
        var homebrewUpped = false
        upHomebrew.meetStub = { _, _ in
            homebrewUpped = true
        }

        // When
        try subject.meet(system: system, projectPath: fileHandler.currentPath)

        // Then
        XCTAssertTrue(homebrewUpped)
        XCTAssertPrinterOutputContains("Adding repository tap: repo")
    }
}
