import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class UpHomebrewTapTests: TuistUnitTestCase {
    var upHomebrew: MockUp!

    override func setUp() {
        super.setUp()
        upHomebrew = MockUp()
    }

    override func tearDown() {
        upHomebrew = nil
        super.tearDown()
    }

    func test_isMet_when_homebrewIsNotMet() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let subject = UpHomebrewTap(repositories: [], upHomebrew: upHomebrew)
        upHomebrew.isMetStub = { _ in false }

        // When
        let got = try subject.isMet(projectPath: temporaryPath)

        // Then
        XCTAssertFalse(got)
    }

    func test_isMet_when_tapsAreMissing() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let subject = UpHomebrewTap(repositories: ["repo"], upHomebrew: upHomebrew)
        upHomebrew.isMetStub = { _ in true }
        system.succeedCommand(["brew", "tap"], output: "")

        // When
        let got = try subject.isMet(projectPath: temporaryPath)

        // Then
        XCTAssertFalse(got)
    }

    func test_isMet_when_allTapsAreConfigured() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let subject = UpHomebrewTap(repositories: ["repo"], upHomebrew: upHomebrew)
        upHomebrew.isMetStub = { _ in true }
        system.succeedCommand(["brew", "tap"], output: "repo\nother\n")

        // When
        let got = try subject.isMet(projectPath: temporaryPath)

        // Then
        XCTAssertTrue(got)
    }

    func test_meet() throws {
        // When
        let temporaryPath = try self.temporaryPath()
        let subject = UpHomebrewTap(repositories: ["repo"], upHomebrew: upHomebrew)
        system.succeedCommand(["brew", "tap"], output: "")
        system.succeedCommand(["brew", "tap", "repo"])
        var homebrewUpped = false
        upHomebrew.meetStub = { _ in
            homebrewUpped = true
        }

        // When
        try subject.meet(projectPath: temporaryPath)

        // Then
        XCTAssertTrue(homebrewUpped)
        XCTAssertPrinterOutputContains("Adding repository tap: repo")
    }
}
