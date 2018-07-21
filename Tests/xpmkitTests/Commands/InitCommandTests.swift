import Basic
import Foundation
@testable import Utility
import XCTest
@testable import xpmkit

final class InitCommandTests: XCTestCase {
    var subject: InitCommand!
    var parser: ArgumentParser!
    var manitestLoader: GraphManifestLoader!
    var graphLoaderContext: GraphLoaderContext!

    override func setUp() {
        super.setUp()
        parser = ArgumentParser.test()
        subject = InitCommand(parser: parser)
        graphLoaderContext = GraphLoaderContext()
        manitestLoader = GraphManifestLoader()
    }

    func test_initCommandError_has_the_right_description_when_alreadyExists() {
        let error = InitCommandError.alreadyExists(AbsolutePath("/path"))
        XCTAssertEqual(error.description, "/path already exists")
    }

    func test_initCommandError_has_the_right_description_when_ungettableProjectName() {
        let error = InitCommandError.ungettableProjectName(AbsolutePath("/path"))
        XCTAssertEqual(error.description, "Couldn't infer the project name from path /path")
    }

    func test_init_registersTheSubparser() {
        XCTAssertTrue(parser.subparsers.keys.contains(InitCommand.command))
    }

    func test_productArgument() {
        XCTAssertEqual(subject.productArgument.name, "--product")
        XCTAssertTrue(subject.productArgument.isOptional)
        XCTAssertEqual(subject.productArgument.usage, "The product (app or framework) the generated project will build.")
        XCTAssertEqual(subject.productArgument.completion, ShellCompletion.values([
            (value: "app", description: "Application"),
            (value: "framework", description: "Framework"),
        ]))
    }

    func test_platformArgument() {
        XCTAssertEqual(subject.platformArgument.name, "--platform")
        XCTAssertTrue(subject.platformArgument.isOptional)
        XCTAssertEqual(subject.platformArgument.usage, "The platform (ios or macos) the product will be for.")
        XCTAssertEqual(subject.platformArgument.completion, ShellCompletion.values([
            (value: "ios", description: "iOS platform"),
            (value: "macos", description: "macOS platform"),
        ]))
    }

    func test_command() throws {

    }
}
