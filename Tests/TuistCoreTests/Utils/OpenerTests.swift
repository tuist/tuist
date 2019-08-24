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

final class OpenerTests: XCTestCase {
    var system: MockSystem!
    var fileHandler: MockFileHandler!
    var subject: Opener!

    override func setUp() {
        super.setUp()
        mockEnvironment()
        fileHandler = sharedMockFileHandler()

        system = MockSystem()
        subject = Opener(system: system)
    }

    func test_open_when_path_doesnt_exist() throws {
        let path = fileHandler.currentPath.appending(component: "tool")

        XCTAssertThrowsError(try subject.open(path: path)) {
            XCTAssertEqual($0 as? OpeningError, OpeningError.notFound(path))
        }
    }

    func test_open() throws {
        let path = fileHandler.currentPath.appending(component: "tool")
        try fileHandler.touch(path)
        system.succeedCommand("/usr/bin/open", path.pathString)
        try subject.open(path: path)
    }
}
