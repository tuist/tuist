import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class UpHomebrewCaskTests: TuistUnitTestCase {
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
        let subject = UpHomebrewCask(projects: [], upHomebrew: upHomebrew)
        upHomebrew.isMetStub = { _ in false }

        // When
        let got = try subject.isMet(projectPath: temporaryPath)

        // Then
        XCTAssertFalse(got)
    }

    func test_isMet_when_casksAreMissing() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let subject = UpHomebrewCask(projects: ["project"], upHomebrew: upHomebrew)
        upHomebrew.isMetStub = { _ in true }
        system.succeedCommand(["brew", "cask"], output: "")

        // When
        let got = try subject.isMet(projectPath: temporaryPath)

        // Then
        XCTAssertFalse(got)
    }

    func test_isMet_when_allCasksAreConfigured() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let subject = UpHomebrewCask(projects: ["project"], upHomebrew: upHomebrew)
        upHomebrew.isMetStub = { _ in true }
        system.succeedCommand(["brew", "cask"], output: "project\nother\n")

        // When
        let got = try subject.isMet(projectPath: temporaryPath)

        // Then
        XCTAssertTrue(got)
    }

    func test_meet() throws {
        // When
        let temporaryPath = try self.temporaryPath()
        let subject = UpHomebrewCask(projects: ["project"], upHomebrew: upHomebrew)
        system.succeedCommand(["brew", "cask"], output: "")
        system.succeedCommand(["brew", "cask", "project"])
        var homebrewUpped = false
        upHomebrew.meetStub = { _ in
            homebrewUpped = true
        }

        // When
        try subject.meet(projectPath: temporaryPath)

        // Then
        XCTAssertTrue(homebrewUpped)
        XCTAssertPrinterOutputContains("Adding repository cask: project")
    }
}
