import Basic
import Foundation
import Utility
import XCTest
@testable import TuistKit

final class InitTests: XCTestCase {
    var initCommand: InitCommand!
    var generateCommand: GenerateCommand!
    var parser: ArgumentParser!
    var directory: TemporaryDirectory!

    override func setUp() {
        parser = ArgumentParser(usage: "test", overview: "test")
        directory = try! TemporaryDirectory(removeTreeOnDeinit: true)
        initCommand = InitCommand(parser: parser)
        generateCommand = GenerateCommand(parser: parser)
    }

    func test_init_when_ios_framework() throws {
        let name = "Test"
        let workspacePath = directory.path.appending(component: "\(name).xcworkspace")
        let initResult = try parser.parse(["init", "--name", name, "--product", "framework", "--platform", "ios", "--path", directory.path.asString])
        try initCommand.run(with: initResult)
        let generateResult = try parser.parse(["generate", "--path", directory.path.asString])
        try generateCommand.run(with: generateResult)
        try Process.checkNonZeroExit(arguments: ["xcodebuild", "-workspace", workspacePath.asString, "-scheme", name, "clean", "build"])
    }

    func test_init_when_macos_framework() throws {
        let name = "Test"
        let workspacePath = directory.path.appending(component: "\(name).xcworkspace")
        let initResult = try parser.parse(["init", "--name", name, "--product", "framework", "--platform", "macos", "--path", directory.path.asString])
        try initCommand.run(with: initResult)
        let generateResult = try parser.parse(["generate", "--path", directory.path.asString])
        try generateCommand.run(with: generateResult)
        try Process.checkNonZeroExit(arguments: ["xcodebuild", "-workspace", workspacePath.asString, "-scheme", name, "clean", "build"])
    }

    func test_init_when_macos_application() throws {
        let name = "Test"
        let workspacePath = directory.path.appending(component: "\(name).xcworkspace")
        let initResult = try parser.parse(["init", "--name", name, "--product", "application", "--platform", "macos", "--path", directory.path.asString])
        try initCommand.run(with: initResult)
        let generateResult = try parser.parse(["generate", "--path", directory.path.asString])
        try generateCommand.run(with: generateResult)
        try Process.checkNonZeroExit(arguments: ["xcodebuild", "-workspace", workspacePath.asString, "-scheme", name, "clean", "build"])
    }
}
