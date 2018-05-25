import Basic
import Foundation
@testable import xcbuddykit
import XCTest

final class GraphModuleLoaderErrorTests: XCTestCase {
    func test_type_when_fileNotFound() {
        let path = AbsolutePath("/test")
        let error = GraphModuleLoaderError.fileNotFound(path)
        XCTAssertEqual(error.type, .abort)
    }

    func test_type_when_fileLoadError() {
        let path = AbsolutePath("/test")
        let error = GraphModuleLoaderError.fileLoadError(path, NSError(domain: "", code: -1, userInfo: nil))
        XCTAssertEqual(error.type, .bugSilent)
    }

    func test_description_when_fileNotFound() {
        let path = AbsolutePath("/test")
        let error = GraphModuleLoaderError.fileNotFound(path)
        XCTAssertEqual(error.description, "File not found at path \(path.asString)")
    }

    func test_description_when_fileLoadError() {
        let path = AbsolutePath("/test")
        let error = GraphModuleLoaderError.fileLoadError(path, NSError(domain: "", code: -1, userInfo: nil))
        XCTAssertEqual(error.description, "Error loading file at path \(path.asString)")
    }
}

final class GraphModuleLoaderTests: XCTestCase {
    var tmpDir: TemporaryDirectory!
    var subject: GraphModuleLoader!
    var context: Context!

    override func setUp() {
        super.setUp()
        tmpDir = try! TemporaryDirectory()
        subject = GraphModuleLoader()
        context = Context()
    }

    override func tearDown() {
        super.tearDown()
        tmpDir = nil
    }

    func test_load() throws {
        let mainSwiftPath = tmpDir.path.appending(component: "main.swift")
        let sharedSwiftPath = tmpDir.path.appending(component: "shared.swift")
        try "//include: ./shared.swift".write(to: URL(fileURLWithPath: mainSwiftPath.asString), atomically: true, encoding: .utf8)
        try "".write(to: URL(fileURLWithPath: sharedSwiftPath.asString), atomically: true, encoding: .utf8)
        let got = try subject.load(mainSwiftPath, context: context)
        XCTAssertTrue(got.contains(mainSwiftPath))
        XCTAssertTrue(got.contains(sharedSwiftPath))
    }

    func test_load_throws_when_theFileDoesntExist() throws {
        let path = tmpDir.path.appending(component: "main.swift")
        XCTAssertThrowsError(try subject.load(path, context: context)) {
            XCTAssertEqual($0 as? GraphModuleLoaderError, GraphModuleLoaderError.fileNotFound(path))
        }
    }
}
