import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class UpMintTests: TuistUnitTestCase {
    var upHomebrew: MockUp!

    override func setUp() {
        super.setUp()
        upHomebrew = MockUp()
    }

    override func tearDown() {
        upHomebrew = nil
        super.tearDown()
    }

    func test_init() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let json = JSON(["linkPackagesGlobally": JSON.bool(true)])

        // When
        let got = try UpMint(dictionary: json, projectPath: temporaryPath)

        // Then
        XCTAssertTrue(got.linkPackagesGlobally)
    }

    func test_isMet_when_homebrew_is_not_met() throws {
        // Given
        let subject = UpMint(linkPackagesGlobally: false, upHomebrew: upHomebrew)
        let temporaryPath = try self.temporaryPath()
        upHomebrew.isMetStub = { _ in false }

        // When
        let got = try subject.isMet(projectPath: temporaryPath)

        // Then
        XCTAssertFalse(got)
    }

    func test_isMet_when_mintfile_is_empty() throws {
        // Given
        let subject = UpMint(linkPackagesGlobally: false, upHomebrew: upHomebrew)
        let temporaryPath = try self.temporaryPath()
        let mintfile = temporaryPath.appending(component: "Mintfile")
        try fileHandler.touch(mintfile)

        upHomebrew.isMetStub = { _ in true }

        // When
        let got = try subject.isMet(projectPath: temporaryPath)

        // Then
        XCTAssertTrue(got)
    }

    func test_isMet_when_mint_packages_are_installed() throws {
        // Given
        let subject = UpMint(linkPackagesGlobally: false, upHomebrew: upHomebrew)
        let temporaryPath = try self.temporaryPath()
        let mintfile = temporaryPath.appending(component: "Mintfile")
        try fileHandler.touch(mintfile)
        let package = "apple/swift-format@swift-5.1-branch"

        upHomebrew.isMetStub = { _ in true }

        system.succeedCommand(["cat", "\(mintfile.pathString)"], output: package)
        system.succeedCommand(["mint", "which", "\(package)"])

        // When
        let got = try subject.isMet(projectPath: temporaryPath)

        // Then
        XCTAssertTrue(got)
    }

    func test_isMet_when_mint_packages_are_not_installed() throws {
        // Given
        let subject = UpMint(linkPackagesGlobally: false, upHomebrew: upHomebrew)
        let temporaryPath = try self.temporaryPath()
        let mintfile = temporaryPath.appending(component: "Mintfile")
        let package = "apple/swift-format@swift-5.1-branch"
        try fileHandler.touch(mintfile)
        try fileHandler.write(package, path: mintfile, atomically: true)

        upHomebrew.isMetStub = { _ in true }

        system.succeedCommand(["cat", "\(mintfile.pathString)"], output: package)
        system.errorCommand(["mint", "which", "\(package)"])

        // When
        let got = try subject.isMet(projectPath: temporaryPath)

        // Then
        XCTAssertFalse(got)
    }

    func test_meet_when_homebrew_is_not_met() throws {
        // Given
        let subject = UpMint(linkPackagesGlobally: false, upHomebrew: upHomebrew)
        let temporaryPath = try self.temporaryPath()
        let mintfile = temporaryPath.appending(component: "Mintfile")
        try fileHandler.touch(mintfile)

        upHomebrew.isMetStub = { _ in false }
        upHomebrew.meetStub = { projectPath in
            XCTAssertEqual(temporaryPath, projectPath)
        }

        system.succeedCommand(["mint", "bootstrap", "-m", "\(mintfile.pathString)"])

        // When
        try subject.meet(projectPath: temporaryPath)

        // Then
        XCTAssertEqual(upHomebrew.meetCallCount, 1)
    }

    func test_meet_when_mintfile_doesnt_exist() throws {
        // Given
        let subject = UpMint(linkPackagesGlobally: false, upHomebrew: upHomebrew)
        let temporaryPath = try self.temporaryPath()

        upHomebrew.isMetStub = { _ in true }

        // Then
        XCTAssertThrowsSpecific(try subject.isMet(projectPath: temporaryPath), UpMintError.mintfileNotFound(temporaryPath))
    }

    func test_meet() throws {
        // Given
        let subject = UpMint(linkPackagesGlobally: false, upHomebrew: upHomebrew)
        let temporaryPath = try self.temporaryPath()
        let mintfile = temporaryPath.appending(component: "Mintfile")
        try fileHandler.touch(mintfile)

        upHomebrew.isMetStub = { _ in true }

        system.succeedCommand(["mint", "bootstrap", "-m", "\(mintfile.pathString)"])

        // When
        try subject.meet(projectPath: temporaryPath)

        // Then
        XCTAssertEqual(upHomebrew.meetCallCount, 0)
    }

    func test_meet_linkPackagesGlobally() throws {
        // Given
        let subject = UpMint(linkPackagesGlobally: true, upHomebrew: upHomebrew)
        let temporaryPath = try self.temporaryPath()
        let mintfile = temporaryPath.appending(component: "Mintfile")
        try fileHandler.touch(mintfile)

        upHomebrew.isMetStub = { _ in true }

        system.succeedCommand(["mint", "bootstrap", "-m", "\(mintfile.pathString)", "--link"])

        // When
        try subject.meet(projectPath: temporaryPath)

        // Then
        XCTAssertEqual(upHomebrew.meetCallCount, 0)
    }
}
