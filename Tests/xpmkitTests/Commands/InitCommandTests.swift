import Basic
import Foundation
@testable import Utility
import XCTest
@testable import xpmcoreTesting
@testable import xpmkit

final class InitCommandErrorTests: XCTestCase {
    func test_description() {
        XCTAssertEqual(InitCommandError.alreadyExists(AbsolutePath("/path")).description, "/path already exists.")
        XCTAssertEqual(InitCommandError.ungettableProjectName(AbsolutePath("/path")).description, "Couldn't infer the project name from path /path.")
    }

    func test_type() {
        XCTAssertEqual(InitCommandError.alreadyExists(AbsolutePath("/path")).type, .abort)
        XCTAssertEqual(InitCommandError.ungettableProjectName(AbsolutePath("/path")).type, .abort)
    }
}

final class InitCommandTests: XCTestCase {
    var subject: InitCommand!
    var parser: ArgumentParser!
    var fileHandler: MockFileHandler!
    var printer: MockPrinter!
    var infoplistProvisioner: InfoPlistProvisioning!

    override func setUp() {
        super.setUp()
        parser = ArgumentParser.test()
        fileHandler = try! MockFileHandler()
        printer = MockPrinter()
        infoplistProvisioner = InfoPlistProvisioner()
        subject = InitCommand(parser: parser,
                              fileHandler: fileHandler,
                              printer: printer,
                              infoplistProvisioner: infoplistProvisioner)
    }

    func test_command() {
        XCTAssertEqual(InitCommand.command, "init")
    }

    func test_overview() {
        XCTAssertEqual(InitCommand.overview, "Bootstraps a project in the current directory.")
    }

    func test_init_registers_the_subparser() {
        XCTAssertTrue(parser.subparsers.keys.contains(InitCommand.command))
    }

    func test_productArgument() {
        XCTAssertEqual(subject.productArgument.name, "--product")
        XCTAssertTrue(subject.productArgument.isOptional)
        XCTAssertEqual(subject.productArgument.usage, "The product (application or framework) the generated project will build.")
        XCTAssertEqual(subject.productArgument.completion, ShellCompletion.values([
            (value: "application", description: "Application"),
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

    func test_nameArgument() {
        XCTAssertEqual(subject.nameArgument.name, "--name")
        XCTAssertEqual(subject.nameArgument.shortName, "-n")

        XCTAssertTrue(subject.nameArgument.isOptional)
        XCTAssertEqual(subject.nameArgument.usage, "The name of the project. If it's not passed, the name of the folder will be used.")
    }

    func test_pathArgument() {
        XCTAssertEqual(subject.pathArgument.name, "--path")
        XCTAssertEqual(subject.pathArgument.shortName, "-p")
        XCTAssertTrue(subject.pathArgument.isOptional)
        XCTAssertEqual(subject.pathArgument.usage, "The path to the folder where the project will be generated.")
        XCTAssertEqual(subject.pathArgument.completion, .filename)
    }

    func test_run_when_ios_application() throws {
        let result = try parser.parse(["init", "--product", "application", "--platform", "ios"])
        try subject.run(with: result)
        let name = fileHandler.currentPath.components.last!
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Project.swift")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Info.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Tests.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Sources/AppDelegate.swift"))))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Tests/\(name)Tests.swift"))))
        XCTAssertEqual(printer.printSuccessArgs.first, "Project generated at path \(fileHandler.currentPath.asString).")
    }

    func test_run_when_macos_application() throws {
        let result = try parser.parse(["init", "--product", "application", "--platform", "macos"])
        try subject.run(with: result)
        let name = fileHandler.currentPath.components.last!
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Project.swift")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Info.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Tests.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Sources/AppDelegate.swift"))))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Tests/\(name)Tests.swift"))))
        XCTAssertEqual(printer.printSuccessArgs.first, "Project generated at path \(fileHandler.currentPath.asString).")
    }

    func test_run_when_ios_framework() throws {
        let result = try parser.parse(["init", "--product", "framework", "--platform", "ios"])
        try subject.run(with: result)
        let name = fileHandler.currentPath.components.last!
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Project.swift")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Info.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Tests.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Sources/\(name).swift"))))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Tests/\(name)Tests.swift"))))
        XCTAssertEqual(printer.printSuccessArgs.first, "Project generated at path \(fileHandler.currentPath.asString).")
    }

    func test_run_when_macos_framework() throws {
        let result = try parser.parse(["init", "--product", "framework", "--platform", "macos"])
        try subject.run(with: result)
        let name = fileHandler.currentPath.components.last!
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Project.swift")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Info.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Tests.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Sources/\(name).swift"))))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Tests/\(name)Tests.swift"))))
        XCTAssertEqual(printer.printSuccessArgs.first, "Project generated at path \(fileHandler.currentPath.asString).")
    }
}
