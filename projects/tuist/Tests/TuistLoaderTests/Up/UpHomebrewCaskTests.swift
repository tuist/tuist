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
        let subject = UpHomebrewCask(projects: ["app"], upHomebrew: upHomebrew)
        upHomebrew.isMetStub = { _ in true }
        system.succeedCommand(["brew", "cask", "list"], output: "")

        // When
        let got = try subject.isMet(projectPath: temporaryPath)

        // Then
        XCTAssertFalse(got)
    }

    func test_isMet_when_allCasksAreConfigured() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let subject = UpHomebrewCask(projects: ["app"], upHomebrew: upHomebrew)
        upHomebrew.isMetStub = { _ in true }
        system.succeedCommand(["brew", "cask", "list"], output: "app\nother\n")

        // When
        let got = try subject.isMet(projectPath: temporaryPath)

        // Then
        XCTAssertTrue(got)
    }

    func test_meet() throws {
        // When
        let temporaryPath = try self.temporaryPath()
        let subject = UpHomebrewCask(projects: ["app"], upHomebrew: upHomebrew)
        system.succeedCommand(["brew", "cask", "list"], output: "")
        system.succeedCommand(["brew", "cask", "install", "app"])
        var homebrewUpped = false
        upHomebrew.meetStub = { _ in
            homebrewUpped = true
        }

        // When
        try subject.meet(projectPath: temporaryPath)

        // Then
        XCTAssertTrue(homebrewUpped)
        XCTAssertPrinterOutputContains("Adding project cask: app")
    }
}
