import Basic
import Foundation
import XCTest

@testable import TuistCore
@testable import TuistCoreTesting

final class OpeningErrorTests: XCTestCase {
    func test_type() {
        let path = AbsolutePath("/test")
        XCTAssertEqual(OpeningError.notFound(path).type, .bug)
    }

    func test_description() {
        let path = AbsolutePath("/test")
        XCTAssertEqual(OpeningError.notFound(path).description, "Couldn't open file at path /test")
    }
}

final class OpenerTests: TuistUnitTestCase {
    var subject: Opener!

    override func setUp() {
        super.setUp()
        subject = Opener()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_open_when_path_doesnt_exist() throws {
        let temporaryPath = try self.temporaryPath()
        let path = temporaryPath.appending(component: "tool")

        XCTAssertThrowsSpecific(try subject.open(path: path), OpeningError.notFound(path))
    }

    func test_open() throws {
        let temporaryPath = try self.temporaryPath()
        let path = temporaryPath.appending(component: "tool")
        try FileHandler.shared.touch(path)
        system.succeedCommand("/usr/bin/open", path.pathString)
        try subject.open(path: path)
    }
}
