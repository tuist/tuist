import Basic
import Foundation
import TuistCore
import TuistGenerator
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
        let temporaryPath = try self.temporaryPath()
        let json = JSON(["linkPackagesGlobally": JSON.bool(true)])
        let got = try UpMint(dictionary: json, projectPath: temporaryPath)
        XCTAssertTrue(got.linkPackagesGlobally)
    }

    func test_isMet_when_homebrew_is_not_met() throws {
        let subject = UpMint(linkPackagesGlobally: false, upHomebrew: upHomebrew)
        let temporaryPath = try self.temporaryPath()

        upHomebrew.isMetStub = { _ in false }

        XCTAssertFalse(try subject.isMet(projectPath: temporaryPath))
    }

    func test_isMet_when_mintfile_doesnt_exist() throws {
        let subject = UpMint(linkPackagesGlobally: false, upHomebrew: upHomebrew)
        let temporaryPath = try self.temporaryPath()

        upHomebrew.isMetStub = { _ in true }

        XCTAssertThrowsError(try subject.isMet(projectPath: temporaryPath)) { error in
            guard let error = error as? UpMint.MintError else {
                XCTFail("Unexpected error type")
                return
            }
            XCTAssertEqual(error.description, "Mintfile not found at path \(temporaryPath.pathString)")
            XCTAssertEqual(error.type, .abort)
        }
    }

    func test_isMet_when_mintfile_is_empty() throws {
        let subject = UpMint(linkPackagesGlobally: false, upHomebrew: upHomebrew)
        let temporaryPath = try self.temporaryPath()
        let mintfile = temporaryPath.appending(component: "Mintfile")
        try fileHandler.touch(mintfile)

        upHomebrew.isMetStub = { _ in true }
        system.succeedCommand(["cat", "\(mintfile.pathString)"])

        XCTAssertTrue(try subject.isMet(projectPath: temporaryPath))
    }

    func test_isMet_when_mint_packages_are_installed() throws {
        let subject = UpMint(linkPackagesGlobally: false, upHomebrew: upHomebrew)
        let temporaryPath = try self.temporaryPath()
        let mintfile = temporaryPath.appending(component: "Mintfile")
        try fileHandler.touch(mintfile)
        let package = "apple/swift-format@swift-5.1-branch"

        upHomebrew.isMetStub = { _ in true }
        system.succeedCommand(["cat", "\(mintfile.pathString)"], output: package)
        system.succeedCommand(["mint", "which", "\(package)"])

        XCTAssertTrue(try subject.isMet(projectPath: temporaryPath))
    }

    func test_isMet_when_mint_packages_are_not_installed() throws {
        let subject = UpMint(linkPackagesGlobally: false, upHomebrew: upHomebrew)
        let temporaryPath = try self.temporaryPath()
        let mintfile = temporaryPath.appending(component: "Mintfile")
        try fileHandler.touch(mintfile)
        let package = "apple/swift-format@swift-5.1-branch"

        upHomebrew.isMetStub = { _ in true }
        system.succeedCommand(["cat", "\(mintfile.pathString)"], output: package)
        system.errorCommand(["mint", "which", "\(package)"])

        XCTAssertFalse(try subject.isMet(projectPath: temporaryPath))
    }

    func test_meet_when_homebrew_is_not_met() throws {
        let subject = UpMint(linkPackagesGlobally: false, upHomebrew: upHomebrew)
        let temporaryPath = try self.temporaryPath()
        let mintfile = temporaryPath.appending(component: "Mintfile")
        try fileHandler.touch(mintfile)
        upHomebrew.isMetStub = { _ in false }

        upHomebrew.meetStub = { projectPath in
            XCTAssertEqual(temporaryPath, projectPath)
        }
        system.succeedCommand(["mint", "bootstrap", "-m", "\(mintfile.pathString)"])

        try subject.meet(projectPath: temporaryPath)

        XCTAssertEqual(upHomebrew.meetCallCount, 1)
    }

    func test_meet_when_mintfile_doesnt_exist() throws {
        let subject = UpMint(linkPackagesGlobally: false, upHomebrew: upHomebrew)
        let temporaryPath = try self.temporaryPath()

        upHomebrew.isMetStub = { _ in true }

        XCTAssertThrowsError(try subject.isMet(projectPath: temporaryPath)) { error in
            guard let error = error as? UpMint.MintError else {
                XCTFail("Unexpected error type")
                return
            }
            XCTAssertEqual(error.description, "Mintfile not found at path \(temporaryPath.pathString)")
            XCTAssertEqual(error.type, .abort)
        }
    }

    func test_meet() throws {
        let subject = UpMint(linkPackagesGlobally: false, upHomebrew: upHomebrew)
        let temporaryPath = try self.temporaryPath()
        let mintfile = temporaryPath.appending(component: "Mintfile")
        try fileHandler.touch(mintfile)

        upHomebrew.isMetStub = { _ in true }
        system.succeedCommand(["mint", "bootstrap", "-m", "\(mintfile.pathString)"])

        try subject.meet(projectPath: temporaryPath)

        XCTAssertEqual(upHomebrew.meetCallCount, 0)
        XCTAssertTrue(system.called("mint bootstrap -m \(mintfile.pathString)"))
    }

    func test_meet_linkPackagesGlobally() throws {
        let subject = UpMint(linkPackagesGlobally: true, upHomebrew: upHomebrew)
        let temporaryPath = try self.temporaryPath()
        let mintfile = temporaryPath.appending(component: "Mintfile")
        try fileHandler.touch(mintfile)

        upHomebrew.isMetStub = { _ in true }
        system.succeedCommand(["mint", "bootstrap", "-m", "\(mintfile.pathString)", "--link"])

        try subject.meet(projectPath: temporaryPath)

        XCTAssertEqual(upHomebrew.meetCallCount, 0)
        XCTAssertTrue(system.called("mint bootstrap -m \(mintfile.pathString) --link"))
    }
}
