import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class UpCarthageTests: TuistUnitTestCase {
    var platforms: [Platform]!
    var upHomebrew: MockUp!
    var carthage: MockCarthage!
    var subject: UpCarthage!

    override func setUp() {
        super.setUp()
        platforms = [.iOS, .macOS]
        carthage = MockCarthage()
        upHomebrew = MockUp()
        subject = UpCarthage(platforms: platforms,
                             upHomebrew: upHomebrew,
                             carthage: carthage)
    }

    override func tearDown() {
        platforms = nil
        carthage = nil
        upHomebrew = nil
        subject = nil
        super.tearDown()
    }

    func test_init() throws {
        let temporaryPath = try self.temporaryPath()
        let json = JSON(["platforms": JSON.array([JSON.string("ios")])])
        let got = try UpCarthage(dictionary: json, projectPath: temporaryPath)
        XCTAssertEqual(got.platforms, [.iOS])
    }

    func test_isMet_when_homebrew_is_not_met() throws {
        let temporaryPath = try self.temporaryPath()

        upHomebrew.isMetStub = { _ in false }
        carthage.outdatedStub = { _ in [] }

        XCTAssertFalse(try subject.isMet(projectPath: temporaryPath))
    }

    func test_isMet_when_carthage_doesnt_have_outdated_dependencies() throws {
        let temporaryPath = try self.temporaryPath()

        upHomebrew.isMetStub = { _ in true }
        carthage.outdatedStub = { _ in nil }

        XCTAssertFalse(try subject.isMet(projectPath: temporaryPath))
    }

    func test_isMet_when_carthage_has_outdated_dependencies() throws {
        let temporaryPath = try self.temporaryPath()

        upHomebrew.isMetStub = { _ in true }
        carthage.outdatedStub = { _ in ["Dependency"] }

        XCTAssertFalse(try subject.isMet(projectPath: temporaryPath))
    }

    func test_isMet() throws {
        let temporaryPath = try self.temporaryPath()

        upHomebrew.isMetStub = { _ in true }
        carthage.outdatedStub = { _ in [] }

        XCTAssertTrue(try subject.isMet(projectPath: temporaryPath))
    }

    func test_meet_when_homebrew_is_not_met() throws {
        let temporaryPath = try self.temporaryPath()
        upHomebrew.isMetStub = { _ in false }

        upHomebrew.meetStub = { projectPath in
            XCTAssertEqual(temporaryPath, projectPath)
        }
        try subject.meet(projectPath: temporaryPath)

        XCTAssertEqual(upHomebrew.meetCallCount, 1)
    }

    func test_meet() throws {
        let temporaryPath = try self.temporaryPath()

        upHomebrew.isMetStub = { _ in true }

        carthage.outdatedStub = { _ in
            ["Dependency"]
        }
        carthage.bootstrapStub = { projectPath, platforms, dependencies in
            XCTAssertEqual(projectPath, temporaryPath)
            XCTAssertEqual(platforms, self.platforms)
            XCTAssertEqual(dependencies, ["Dependency"])
        }

        try subject.meet(projectPath: temporaryPath)

        XCTAssertEqual(upHomebrew.meetCallCount, 0)
        XCTAssertEqual(carthage.bootstrapCallCount, 1)
    }
}
