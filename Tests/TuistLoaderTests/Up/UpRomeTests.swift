import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest
import TuistGraph
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
        //  Given
        let temporaryPath = try self.temporaryPath()
        let json = JSON(["platforms": JSON.array([JSON.string("ios")]), "cachePrefix": "Swift_5_1"])

        //  Then
        let got = try UpRome(dictionary: json, projectPath: temporaryPath)

        //  When
        XCTAssertEqual(got.platforms, [.iOS])
        XCTAssertEqual(got.cachePrefix, "Swift_5_1")
    }

    func test_nil_init_params() throws {
        //  Given
        let temporaryPath = try self.temporaryPath()
        let json = JSON([:])

        //  Then
        let got = try UpRome(dictionary: json, projectPath: temporaryPath)

        //  When
        XCTAssertEqual(got.platforms, [])
        XCTAssertNil(got.cachePrefix)
    }

    func test_isMet_when_rome_is_not_met() throws {
        //  Given
        let temporaryPath = try self.temporaryPath()
        upHomebrew.isMetStub = { _ in false }
        rome.downloadStub = { _, _ in }

        //  Then
        let result = try subject.isMet(projectPath: temporaryPath)

        //  When
        XCTAssertFalse(result)
    }

    func test_isMet() throws {
        //  Given
        let temporaryPath = try self.temporaryPath()

        upHomebrew.isMetStub = { _ in true }
        rome.downloadStub = { _, _ in }

        //  Then
        let result = try subject.isMet(projectPath: temporaryPath)

        //  When
        XCTAssertFalse(result)
    }

    func test_when_not_isMet() throws {
        //  Given
        let temporaryPath = try self.temporaryPath()

        upHomebrew.isMetStub = { _ in false }
        rome.downloadStub = { _, _ in }

        //  Then
        let result = try subject.isMet(projectPath: temporaryPath)

        //  When
        XCTAssertFalse(result)
    }

    func test_meet_when_homebrew_is_not_met() throws {
        //  Given
        let temporaryPath = try self.temporaryPath()
        upHomebrew.isMetStub = { _ in false }

        upHomebrew.meetStub = { projectPath in
            XCTAssertEqual(temporaryPath, projectPath)
        }

        //  Then
        try subject.meet(projectPath: temporaryPath)

        //  When
        XCTAssertEqual(upHomebrew.meetCallCount, 1)
    }

    func test_meet() throws {
        //  Given
        let temporaryPath = try self.temporaryPath()
        upHomebrew.isMetStub = { _ in true }

        rome.downloadStub = { platforms, cachePrefix in
            XCTAssertEqual(platforms, self.platforms)
            XCTAssertEqual(cachePrefix, self.cachePrefix)
        }

        //  Then
        try subject.meet(projectPath: temporaryPath)

        // When
        XCTAssertEqual(upHomebrew.meetCallCount, 0)
        XCTAssertEqual(rome.downloadCallCount, 1)
    }
}
