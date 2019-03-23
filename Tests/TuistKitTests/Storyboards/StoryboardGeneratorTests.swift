import Basic
import Foundation
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

final class StoryboardGenerationErrorTests: XCTestCase {
    func test_description() {
        XCTAssertEqual(StoryboardGenerationError.alreadyExisting(AbsolutePath("/Launch Screen.storyboard")).description, "A storyboard already exists at path /Launch Screen.storyboard")
        XCTAssertEqual(StoryboardGenerationError.launchScreenUnsupported(.macOS, .framework).description, "A macOS framework does not support a launch screen storyboard")
    }

    func test_type() {
        XCTAssertEqual(StoryboardGenerationError.alreadyExisting(AbsolutePath("/Launch Screen.storyboard")).type, .abort)
        XCTAssertEqual(StoryboardGenerationError.launchScreenUnsupported(.macOS, .framework).type, .abort)
    }
}

final class StoryboardGeneratorTests: XCTestCase {
    var fileHandler: MockFileHandler!
    var subject: StoryboardGenerator!

    override func setUp() {
        super.setUp()
        fileHandler = try! MockFileHandler()
        subject = StoryboardGenerator(fileHandler: fileHandler)
    }

    func test_generate_throws_when_main_storyboard_exists() throws {
        let storyboardPath = fileHandler.currentPath.appending(component: "Test.storyboard")
        let expectedError = StoryboardGenerationError.alreadyExisting(storyboardPath)
        try fileHandler.touch(storyboardPath)

        XCTAssertThrowsError(try subject.generateMain(path: fileHandler.currentPath,
                                                      name: "Test",
                                                      platform: .iOS)) {
            XCTAssertEqual($0 as? StoryboardGenerationError, expectedError)
        }
    }

    func test_generate_throws_when_launch_storyboard_exists() throws {
        let storyboardPath = fileHandler.currentPath.appending(component: "Test.storyboard")
        let expectedError = StoryboardGenerationError.alreadyExisting(storyboardPath)
        try fileHandler.touch(storyboardPath)

        XCTAssertThrowsError(try subject.generateLaunchScreen(path: fileHandler.currentPath,
                                                              name: "Test",
                                                              platform: .iOS,
                                                              product: .app)) {
            XCTAssertEqual($0 as? StoryboardGenerationError, expectedError)
        }
    }

    func test_generate_throws_when_launch_screen_unsupported_by_platform() throws {
        let expectedError = StoryboardGenerationError.launchScreenUnsupported(.tvOS, .app)

        XCTAssertThrowsError(try subject.generateLaunchScreen(path: fileHandler.currentPath,
                                                              name: "Test",
                                                              platform: .tvOS,
                                                              product: .app)) {
            XCTAssertEqual($0 as? StoryboardGenerationError, expectedError)
        }
    }

    func test_generate_writes_xcstoryboard() throws {
        let storyboardPath = fileHandler.currentPath.appending(component: "Test.storyboard")
        try subject.generateMain(path: fileHandler.currentPath,
                                 name: "Test",
                                 platform: .iOS)

        let xcstoryboard = try String(contentsOf: storyboardPath.url, encoding: .utf8)
        XCTAssertEqual(xcstoryboard, StoryboardGenerator.xcstoarybaordContent(platform: .iOS))
    }
}
