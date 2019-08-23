import Basic
import Foundation
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

final class PlaygroundGenerationErrorTests: XCTestCase {
    func test_description() {
        XCTAssertEqual(PlaygroundGenerationError.alreadyExisting(AbsolutePath("/test.playground")).description, "A playground already exists at path /test.playground")
    }

    func test_type() {
        XCTAssertEqual(PlaygroundGenerationError.alreadyExisting(AbsolutePath("/test.playground")).type, .abort)
    }
}

final class PlaygroundGeneratorTests: XCTestCase {
    var fileHandler: MockFileHandler!
    var subject: PlaygroundGenerator!

    override func setUp() {
        super.setUp()
        mockEnvironment()
        fileHandler = sharedMockFileHandler()

        subject = PlaygroundGenerator()
    }

    func test_generate_throws_when_playground_exists() throws {
        let playgroundPath = fileHandler.currentPath.appending(component: "Test.playground")
        try fileHandler.createFolder(playgroundPath)
        let expectedError = PlaygroundGenerationError.alreadyExisting(playgroundPath)

        XCTAssertThrowsError(try subject.generate(path: fileHandler.currentPath,
                                                  name: "Test",
                                                  platform: .iOS)) {
            XCTAssertEqual($0 as? PlaygroundGenerationError, expectedError)
        }
    }

    func test_generate_writes_content() throws {
        let playgroundPath = fileHandler.currentPath.appending(component: "Test.playground")
        try subject.generate(path: fileHandler.currentPath,
                             name: "Test",
                             platform: .iOS,
                             content: "Test")

        let contentsPath = playgroundPath.appending(component: "Contents.swift")
        let content = try String(contentsOf: contentsPath.url,
                                 encoding: .utf8)
        XCTAssertEqual(content, "Test")
    }

    func test_generate_writes_default_content() throws {
        let playgroundPath = fileHandler.currentPath.appending(component: "Test.playground")
        try subject.generate(path: fileHandler.currentPath,
                             name: "Test",
                             platform: .iOS)

        let contentsPath = playgroundPath.appending(component: "Contents.swift")
        let content = try String(contentsOf: contentsPath.url,
                                 encoding: .utf8)
        XCTAssertEqual(content, PlaygroundGenerator.defaultContent())
    }

    func test_generate_writes_xcplayground() throws {
        let playgroundPath = fileHandler.currentPath.appending(component: "Test.playground")
        try subject.generate(path: fileHandler.currentPath,
                             name: "Test",
                             platform: .iOS)

        let xcplaygroundPath = playgroundPath.appending(component: "contents.xcplayground")
        let xcplayground = try String(contentsOf: xcplaygroundPath.url,
                                      encoding: .utf8)
        XCTAssertEqual(xcplayground, PlaygroundGenerator.xcplaygroundContent(platform: .iOS))
    }
}
