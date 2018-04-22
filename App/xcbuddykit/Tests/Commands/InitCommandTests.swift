import Foundation
import Basic
import XCTest

@testable import Utility
@testable import xcbuddykit

final class InitCommandTests: XCTestCase {
    
    var subject: InitCommand!
    var argumentParser: ArgumentParser!
    
    override func setUp() {
        super.setUp()
        argumentParser = ArgumentParser.test()
        subject = InitCommand(parser: argumentParser)
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
        XCTAssertTrue(argumentParser.subparsers.keys.contains(subject.command))
    }
    
    func test_pathArgument() {
        XCTAssertEqual(subject.pathArgument.shortName, "-p")
        XCTAssertEqual(subject.pathArgument.usage, "The path where the Project.swift file will be generated")
        XCTAssertEqual(subject.pathArgument.completion, ShellCompletion.filename)

    }
    
    func test_command() throws {
        let tmpDir = try TemporaryDirectory()

    }
}
