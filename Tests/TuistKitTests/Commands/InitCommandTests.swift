import Basic
import Foundation
@testable import TuistCoreTesting
@testable import TuistKit
@testable import Utility
import XCTest

final class InitCommandErrorTests: XCTestCase {
    func test_description() {
        XCTAssertEqual(InitCommandError.alreadyExists(AbsolutePath("/path")).description, "/path already exists.")
        XCTAssertEqual(InitCommandError.ungettableProjectName(AbsolutePath("/path")).description, "Couldn't infer the project name from path /path.")
        XCTAssertEqual(InitCommandError.nonEmptyDirectory(AbsolutePath("/path")).description, "Can't initialize a project in the non-empty directory at path /path.")

    }

    func test_type() {
        XCTAssertEqual(InitCommandError.alreadyExists(AbsolutePath("/path")).type, .abort)
        XCTAssertEqual(InitCommandError.ungettableProjectName(AbsolutePath("/path")).type, .abort)
        XCTAssertEqual(InitCommandError.nonEmptyDirectory(AbsolutePath("/path")).type, .abort)
    }
}

final class InitCommandTests: XCTestCase {
    var subject: InitCommand!
    var parser: ArgumentParser!
    var fileHandler: MockFileHandler!
    var printer: MockPrinter!
    var infoplistProvisioner: InfoPlistProvisioning!
    var playgroundGenerator: MockPlaygroundGenerator!

    override func setUp() {
        super.setUp()
        parser = ArgumentParser.test()
        fileHandler = try! MockFileHandler()
        printer = MockPrinter()
        infoplistProvisioner = InfoPlistProvisioner()
        playgroundGenerator = MockPlaygroundGenerator()
        subject = InitCommand(parser: parser,
                              fileHandler: fileHandler,
                              printer: printer,
                              infoplistProvisioner: infoplistProvisioner,
                              playgroundGenerator: playgroundGenerator)
    }

    func test_command() {
        XCTAssertEqual(InitCommand.command, "init")
    }

    func test_overview() {
        XCTAssertEqual(InitCommand.overview, "Bootstraps a project.")
    }

    func test_init_registers_the_subparser() {
        XCTAssertTrue(parser.subparsers.keys.contains(InitCommand.command))
    }

    func test_productArgument() {
        XCTAssertEqual(subject.productArgument.name, "--product")
        XCTAssertTrue(subject.productArgument.isOptional)
        XCTAssertEqual(subject.productArgument.usage, "The product (application or framework) the generated project will build (Default: application).")
        XCTAssertEqual(subject.productArgument.completion, ShellCompletion.values([
            (value: "application", description: "Application"),
            (value: "framework", description: "Framework"),
        ]))
    }

    func test_platformArgument() {
        XCTAssertEqual(subject.platformArgument.name, "--platform")
        XCTAssertTrue(subject.platformArgument.isOptional)
        XCTAssertEqual(subject.platformArgument.usage, "The platform (ios, tvos or macos) the product will be for (Default: ios).")
        XCTAssertEqual(subject.platformArgument.completion, ShellCompletion.values([
            (value: "ios", description: "iOS platform"),
            (value: "tvos", description: "tvOS platform"),
            (value: "macos", description: "macOS platform"),
        ]))
    }

    func test_nameArgument() {
        XCTAssertEqual(subject.nameArgument.name, "--name")
        XCTAssertEqual(subject.nameArgument.shortName, "-n")

        XCTAssertTrue(subject.nameArgument.isOptional)
        XCTAssertEqual(subject.nameArgument.usage, "The name of the project. If it's not passed (Default: Name of the directory).")
    }

    func test_pathArgument() {
        XCTAssertEqual(subject.pathArgument.name, "--path")
        XCTAssertEqual(subject.pathArgument.shortName, "-p")
        XCTAssertTrue(subject.pathArgument.isOptional)
        XCTAssertEqual(subject.pathArgument.usage, "The path to the folder where the project will be generated (Default: Current directory).")
        XCTAssertEqual(subject.pathArgument.completion, .filename)
    }
    
    func test_run_when_the_directory_is_not_empty() throws {
        let path = fileHandler.currentPath
        try fileHandler.touch(path.appending(component: "dummy"))
        
        let result = try parser.parse(["init", "--path", path.asString, "--name", "Test"])
        
        XCTAssertThrowsError(try subject.run(with: result)) { error in
            let expected = InitCommandError.nonEmptyDirectory(path)
            XCTAssertEqual(error as? InitCommandError, expected)
        }
    }

    func test_run_when_ios_application() throws {
        let result = try parser.parse(["init", "--product", "application", "--platform", "ios"])
        try subject.run(with: result)
        let name = fileHandler.currentPath.components.last!
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: ".gitignore")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Project.swift")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Info.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Tests.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Sources/AppDelegate.swift"))))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Tests/\(name)Tests.swift"))))
        XCTAssertEqual(printer.printSuccessArgs.first, "Project generated at path \(fileHandler.currentPath.asString).")

        let playgroundsPath = fileHandler.currentPath.appending(component: "Playgrounds")
        XCTAssertTrue(fileHandler.exists(playgroundsPath))
        XCTAssertEqual(playgroundGenerator.generateCallCount, 1)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.0, playgroundsPath)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.1, name)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.2, .iOS)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.3, PlaygroundGenerator.defaultContent())
    }

    func test_run_when_tvos_application() throws {
        let result = try parser.parse(["init", "--product", "application", "--platform", "tvos"])
        try subject.run(with: result)
        let name = fileHandler.currentPath.components.last!
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: ".gitignore")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Project.swift")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Info.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Tests.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Sources/AppDelegate.swift"))))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Tests/\(name)Tests.swift"))))
        XCTAssertEqual(printer.printSuccessArgs.first, "Project generated at path \(fileHandler.currentPath.asString).")

        let playgroundsPath = fileHandler.currentPath.appending(component: "Playgrounds")
        XCTAssertTrue(fileHandler.exists(playgroundsPath))
        XCTAssertEqual(playgroundGenerator.generateCallCount, 1)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.0, playgroundsPath)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.1, name)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.2, .tvOS)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.3, PlaygroundGenerator.defaultContent())
    }

    func test_run_when_macos_application() throws {
        let result = try parser.parse(["init", "--product", "application", "--platform", "macos"])
        try subject.run(with: result)
        let name = fileHandler.currentPath.components.last!
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: ".gitignore")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Project.swift")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Info.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Tests.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Sources/AppDelegate.swift"))))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Tests/\(name)Tests.swift"))))
        XCTAssertEqual(printer.printSuccessArgs.first, "Project generated at path \(fileHandler.currentPath.asString).")

        let playgroundsPath = fileHandler.currentPath.appending(component: "Playgrounds")
        XCTAssertTrue(fileHandler.exists(playgroundsPath))
        XCTAssertEqual(playgroundGenerator.generateCallCount, 1)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.0, playgroundsPath)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.1, name)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.2, .macOS)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.3, PlaygroundGenerator.defaultContent())
    }

    func test_run_when_ios_framework() throws {
        let result = try parser.parse(["init", "--product", "framework", "--platform", "ios"])
        try subject.run(with: result)
        let name = fileHandler.currentPath.components.last!
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: ".gitignore")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Project.swift")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Info.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Tests.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Sources/\(name).swift"))))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Tests/\(name)Tests.swift"))))
        XCTAssertEqual(printer.printSuccessArgs.first, "Project generated at path \(fileHandler.currentPath.asString).")

        let playgroundsPath = fileHandler.currentPath.appending(component: "Playgrounds")
        XCTAssertTrue(fileHandler.exists(playgroundsPath))
        XCTAssertEqual(playgroundGenerator.generateCallCount, 1)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.0, playgroundsPath)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.1, name)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.2, .iOS)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.3, PlaygroundGenerator.defaultContent())
    }

    func test_run_when_tvos_framework() throws {
        let result = try parser.parse(["init", "--product", "framework", "--platform", "tvos"])
        try subject.run(with: result)
        let name = fileHandler.currentPath.components.last!
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: ".gitignore")))

        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Project.swift")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Info.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Tests.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Sources/\(name).swift"))))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Tests/\(name)Tests.swift"))))
        XCTAssertEqual(printer.printSuccessArgs.first, "Project generated at path \(fileHandler.currentPath.asString).")

        let playgroundsPath = fileHandler.currentPath.appending(component: "Playgrounds")
        XCTAssertTrue(fileHandler.exists(playgroundsPath))
        XCTAssertEqual(playgroundGenerator.generateCallCount, 1)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.0, playgroundsPath)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.1, name)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.2, .tvOS)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.3, PlaygroundGenerator.defaultContent())
    }

    func test_run_when_macos_framework() throws {
        let result = try parser.parse(["init", "--product", "framework", "--platform", "macos"])
        try subject.run(with: result)
        let name = fileHandler.currentPath.components.last!
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: ".gitignore")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Project.swift")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Info.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(component: "Tests.plist")))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Sources/\(name).swift"))))
        XCTAssertTrue(fileHandler.exists(fileHandler.currentPath.appending(RelativePath("Tests/\(name)Tests.swift"))))
        XCTAssertEqual(printer.printSuccessArgs.first, "Project generated at path \(fileHandler.currentPath.asString).")

        let playgroundsPath = fileHandler.currentPath.appending(component: "Playgrounds")
        XCTAssertTrue(fileHandler.exists(playgroundsPath))
        XCTAssertEqual(playgroundGenerator.generateCallCount, 1)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.0, playgroundsPath)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.1, name)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.2, .macOS)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.3, PlaygroundGenerator.defaultContent())
    }
}
