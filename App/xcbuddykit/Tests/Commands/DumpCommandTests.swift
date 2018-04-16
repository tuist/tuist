import Foundation
import PathKit
@testable import xcbuddykit
import XCTest

final class DumpCommandTests: XCTestCase {
    var manifestLoader: MockGraphManifestLoader!
    var fileHandler: MockFileHandler!
    var subject: DumpCommand!
    var printer: MockPrinter!

    override func setUp() {
        super.setUp()
        manifestLoader = MockGraphManifestLoader()
        fileHandler = MockFileHandler()
        printer = MockPrinter()
        subject = DumpCommand(manifestLoader: manifestLoader,
                              fileHandler: fileHandler,
                              printer: printer)
    }

    func test_name_has_the_right_value() {
        XCTAssertEqual(subject.name, "dump")
    }

    func test_shortDescription_has_the_right_value() {
        XCTAssertEqual(subject.shortDescription, "Prints parsed Project.swift, Workspace.swift, or Config.swift as JSON")
    }

    func test_execute_throws_if_the_file_doesnt_exist() throws {
        subject.path.update(value: "path/to/Project.swift")
        fileHandler.currentPathStub = "/absolute/"
        fileHandler.isRelativeStub = { path in
            path == Path("path/to/Project.swift")
        }
        fileHandler.existsStub = { path in
            path != Path("/absolute/path/to/Project.swift")
        }
        do {
            try subject.execute()
        } catch let error as String {
            XCTAssertEqual(error, "Path /absolute/path/to/Project.swift doesn't exist")
            return
        }
        XCTFail("It should have failed but it didn't")
    }

    func test_execute_throws_if_manifestLoader_throws() throws {
        subject.path.update(value: "path/to/Project.swift")
        fileHandler.currentPathStub = "/absolute/"
        fileHandler.isRelativeStub = { _ in true }
        fileHandler.existsStub = { _ in true }
        manifestLoader.loadStub = { _ in
            throw "Test error"
        }
        do {
            try subject.execute()
        } catch let error as String {
            XCTAssertEqual(error, "Test error")
            return
        }
        XCTFail("It should have failed but it didn't")
    }

    func test_execute_prints_the_string_representation_of_the_json_data_returned_by_the_manifest() throws {
        subject.path.update(value: "path/to/Project.swift")
        fileHandler.currentPathStub = "/absolute/"
        fileHandler.isRelativeStub = { _ in true }
        fileHandler.existsStub = { _ in true }
        manifestLoader.loadStub = { path in
            try Data.testJson(["path": path.string])
        }
        try subject.execute()
        let expected = "{\"path\":\"\\/absolute\\/path\\/to\\/Project.swift\"}"
        XCTAssertEqual(printer.printArgs.last, expected)
    }
}
