import Basic
import Foundation
import TuistCore
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

final class PlaygroundGeneratorTests: TuistUnitTestCase {
    var subject: PlaygroundGenerator!

    override func setUp() {
        super.setUp()
        subject = PlaygroundGenerator()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_generate_throws_when_playground_exists() throws {
        let temporaryPath = try self.temporaryPath()
        let playgroundPath = temporaryPath.appending(component: "Test.playground")
        try FileHandler.shared.createFolder(playgroundPath)

        XCTAssertThrowsSpecific(try subject.generate(path: temporaryPath,
                                                     name: "Test",
                                                     platform: .iOS),
                                PlaygroundGenerationError.alreadyExisting(playgroundPath))
    }

    func test_generate_writes_content() throws {
        let temporaryPath = try self.temporaryPath()
        let playgroundPath = temporaryPath.appending(component: "Test.playground")
        try subject.generate(path: temporaryPath,
                             name: "Test",
                             platform: .iOS,
                             content: "Test")

        let contentsPath = playgroundPath.appending(component: "Contents.swift")
        let content = try String(contentsOf: contentsPath.url,
                                 encoding: .utf8)
        XCTAssertEqual(content, "Test")
    }

    func test_generate_writes_default_content() throws {
        let temporaryPath = try self.temporaryPath()
        let playgroundPath = temporaryPath.appending(component: "Test.playground")
        try subject.generate(path: temporaryPath,
                             name: "Test",
                             platform: .iOS)

        let contentsPath = playgroundPath.appending(component: "Contents.swift")
        let content = try String(contentsOf: contentsPath.url,
                                 encoding: .utf8)
        XCTAssertEqual(content, PlaygroundGenerator.defaultContent())
    }

    func test_generate_writes_xcplayground() throws {
        let temporaryPath = try self.temporaryPath()
        let playgroundPath = temporaryPath.appending(component: "Test.playground")
        try subject.generate(path: temporaryPath,
                             name: "Test",
                             platform: .iOS)

        let xcplaygroundPath = playgroundPath.appending(component: "contents.xcplayground")
        let xcplayground = try String(contentsOf: xcplaygroundPath.url,
                                      encoding: .utf8)
        XCTAssertEqual(xcplayground, PlaygroundGenerator.xcplaygroundContent(platform: .iOS))
    }
}
