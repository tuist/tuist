import Basic
import Foundation
import TuistCore
import XCTest
import TuistGenerator
@testable import TuistCoreTesting
@testable import TuistKit

final class UpCarthageTests: XCTestCase {
    var platforms: [Platform]!
    var upHomebrew: MockUp!
    var carthage: MockCarthage!
    var subject: UpCarthage!
    var fileHandler: MockFileHandler!
    var system: MockSystem!
    var printer: MockPrinter!

    override func setUp() {
        super.setUp()
        platforms = [.iOS, .macOS]
        carthage = MockCarthage()
        upHomebrew = MockUp()
        fileHandler = try! MockFileHandler()
        system = MockSystem()
        printer = MockPrinter()
        subject = UpCarthage(platforms: platforms,
                             upHomebrew: upHomebrew,
                             carthage: carthage)
    }

    func test_init() throws {
        let json = JSON(["platforms": JSON.array([JSON.string("ios")])])
        let got = try UpCarthage(dictionary: json,
                                 projectPath: fileHandler.currentPath,
                                 fileHandler: fileHandler)
        XCTAssertEqual(got.platforms, [.iOS])
    }

    func test_isMet_when_homebrew_is_not_met() throws {
        upHomebrew.isMetStub = { _, _ in false }
        carthage.outdatedStub = { _ in [] }

        XCTAssertFalse(try subject.isMet(system: system, projectPath: fileHandler.currentPath))
    }

    func test_isMet_when_carthage_doesnt_have_outdated_dependencies() throws {
        upHomebrew.isMetStub = { _, _ in true }
        carthage.outdatedStub = { _ in nil }

        XCTAssertFalse(try subject.isMet(system: system, projectPath: fileHandler.currentPath))
    }

    func test_isMet_when_carthage_has_outdated_dependencies() throws {
        upHomebrew.isMetStub = { _, _ in true }
        carthage.outdatedStub = { _ in ["Dependency"] }

        XCTAssertFalse(try subject.isMet(system: system, projectPath: fileHandler.currentPath))
    }

    func test_isMet() throws {
        upHomebrew.isMetStub = { _, _ in true }
        carthage.outdatedStub = { _ in [] }

        XCTAssertTrue(try subject.isMet(system: system, projectPath: fileHandler.currentPath))
    }

    func test_meet_when_homebrew_is_not_met() throws {
        upHomebrew.isMetStub = { _, _ in false }

        upHomebrew.meetStub = { _, _, projectPath in
            XCTAssertEqual(self.fileHandler.currentPath, projectPath)
        }
        try subject.meet(system: system, printer: printer, projectPath: fileHandler.currentPath)

        XCTAssertEqual(upHomebrew.meetCallCount, 1)
    }

    func test_meet() throws {
        upHomebrew.isMetStub = { _, _ in true }

        carthage.outdatedStub = { _ in
            ["Dependency"]
        }
        carthage.updateStub = { projectPath, platforms, dependencies in
            XCTAssertEqual(projectPath, self.fileHandler.currentPath)
            XCTAssertEqual(platforms, self.platforms)
            XCTAssertEqual(dependencies, ["Dependency"])
        }

        try subject.meet(system: system,
                         printer: printer,
                         projectPath: fileHandler.currentPath)

        XCTAssertEqual(upHomebrew.meetCallCount, 0)
        XCTAssertEqual(carthage.updateCallCount, 1)
    }
}
