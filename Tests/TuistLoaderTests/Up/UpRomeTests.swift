import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class UpRomeTests: TuistUnitTestCase {
    var platforms: [Platform]!
    var cachePrefix: String!
    var upHomebrew: MockUp!
    var rome: MockRome!
    var subject: UpRome!

    override func setUp() {
        super.setUp()
        platforms = [.iOS]
        cachePrefix = "Swift_1_2"
        rome = MockRome()
        upHomebrew = MockUp()
        subject = UpRome(platforms: platforms,
                         cachePrefix: cachePrefix,
                         upHomebrew: upHomebrew,
                         rome: rome)
    }

    override func tearDown() {
        platforms = nil
        cachePrefix = nil
        rome = nil
        upHomebrew = nil
        subject = nil
        super.tearDown()
    }

    func test_init() throws {
        let temporaryPath = try self.temporaryPath()
        let json = JSON(["platforms": JSON.array([JSON.string("ios")]), "cachePrefix": "Swift_5_1"])
        let got = try UpRome(dictionary: json, projectPath: temporaryPath)
        XCTAssertEqual(got.platforms, [.iOS])
        XCTAssertEqual(got.cachePrefix, "Swift_5_1")
    }

    func test_isMet_when_rome_is_not_met() throws {
        let temporaryPath = try self.temporaryPath()

        upHomebrew.isMetStub = { _ in false }
        rome.downloadStub = { _, _ in }

        XCTAssertFalse(try subject.isMet(projectPath: temporaryPath))
    }

    func test_isMet() throws {
        let temporaryPath = try self.temporaryPath()

        upHomebrew.isMetStub = { _ in true }
        rome.downloadStub = { _, _ in }

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

        rome.downloadStub = { platforms, cachePrefix in
            XCTAssertEqual(platforms, self.platforms)
            XCTAssertEqual(cachePrefix, self.cachePrefix)
        }

        try subject.meet(projectPath: temporaryPath)

        XCTAssertEqual(upHomebrew.meetCallCount, 0)
        XCTAssertEqual(rome.downloadCallCount, 1)
    }
}
