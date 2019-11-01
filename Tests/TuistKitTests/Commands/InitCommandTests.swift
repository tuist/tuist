import Basic
import Foundation
import TuistSupport
import XCTest

@testable import SPMUtility
@testable import TuistKit
@testable import TuistSupportTesting

final class InitCommandErrorTests: XCTestCase {
    func test_description() {
        XCTAssertEqual(InitCommandError.ungettableProjectName(AbsolutePath("/path")).description, "Couldn't infer the project name from path /path.")
        XCTAssertEqual(InitCommandError.nonEmptyDirectory(AbsolutePath("/path")).description, "Can't initialize a project in the non-empty directory at path /path.")
    }

    func test_type() {
        XCTAssertEqual(InitCommandError.ungettableProjectName(AbsolutePath("/path")).type, .abort)
        XCTAssertEqual(InitCommandError.nonEmptyDirectory(AbsolutePath("/path")).type, .abort)
    }
}

final class InitCommandTests: TuistUnitTestCase {
    var subject: InitCommand!
    var parser: ArgumentParser!
    var infoplistProvisioner: InfoPlistProvisioning!
    var playgroundGenerator: MockPlaygroundGenerator!

    override func setUp() {
        super.setUp()
        parser = ArgumentParser.test()
        infoplistProvisioner = InfoPlistProvisioner()
        playgroundGenerator = MockPlaygroundGenerator()
        subject = InitCommand(parser: parser,
                              infoplistProvisioner: infoplistProvisioner,
                              playgroundGenerator: playgroundGenerator)
    }

    override func tearDown() {
        subject = nil
        parser = nil
        infoplistProvisioner = nil
        playgroundGenerator = nil

        super.tearDown()
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
        let temporaryPath = try self.temporaryPath()
        try FileHandler.shared.touch(temporaryPath.appending(component: "dummy"))

        let result = try parser.parse(["init", "--path", temporaryPath.pathString, "--name", "Test"])

        XCTAssertThrowsSpecific(try subject.run(with: result), InitCommandError.nonEmptyDirectory(temporaryPath))
    }

    func test_run_when_ios_application() throws {
        let result = try parser.parse(["init", "--product", "application", "--platform", "ios"])
        try subject.run(with: result)
        let temporaryPath = try self.temporaryPath()

        let name = temporaryPath.basename
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: ".gitignore")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Project.swift")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "TuistConfig.swift")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Setup.swift")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Info.plist")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Tests.plist")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(RelativePath("Sources/AppDelegate.swift"))))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(RelativePath("Tests/\(name)Tests.swift"))))
        XCTAssertPrinterOutputContains("Project generated at path \(temporaryPath.pathString).")

        let playgroundsPath = temporaryPath.appending(component: "Playgrounds")
        XCTAssertTrue(FileHandler.shared.exists(playgroundsPath))
        XCTAssertEqual(playgroundGenerator.generateCallCount, 1)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.0, playgroundsPath)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.1, name)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.2, .iOS)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.3, PlaygroundGenerator.defaultContent())
    }

    func test_run_when_tvos_application() throws {
        let result = try parser.parse(["init", "--product", "application", "--platform", "tvos"])
        try subject.run(with: result)
        let temporaryPath = try self.temporaryPath()

        let name = temporaryPath.basename
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: ".gitignore")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Project.swift")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "TuistConfig.swift")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Setup.swift")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Info.plist")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Tests.plist")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(RelativePath("Sources/AppDelegate.swift"))))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(RelativePath("Tests/\(name)Tests.swift"))))
        XCTAssertPrinterOutputContains("Project generated at path \(temporaryPath.pathString).")

        let playgroundsPath = temporaryPath.appending(component: "Playgrounds")
        XCTAssertTrue(FileHandler.shared.exists(playgroundsPath))
        XCTAssertEqual(playgroundGenerator.generateCallCount, 1)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.0, playgroundsPath)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.1, name)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.2, .tvOS)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.3, PlaygroundGenerator.defaultContent())
    }

    func test_run_when_macos_application() throws {
        let result = try parser.parse(["init", "--product", "application", "--platform", "macos"])
        try subject.run(with: result)
        let temporaryPath = try self.temporaryPath()

        let name = temporaryPath.basename
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: ".gitignore")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Project.swift")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Setup.swift")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Info.plist")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Tests.plist")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(RelativePath("Sources/AppDelegate.swift"))))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(RelativePath("Tests/\(name)Tests.swift"))))
        XCTAssertPrinterOutputContains("Project generated at path \(temporaryPath.pathString).")

        let playgroundsPath = temporaryPath.appending(component: "Playgrounds")
        XCTAssertTrue(FileHandler.shared.exists(playgroundsPath))
        XCTAssertEqual(playgroundGenerator.generateCallCount, 1)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.0, playgroundsPath)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.1, name)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.2, .macOS)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.3, PlaygroundGenerator.defaultContent())
    }

    func test_run_when_ios_framework() throws {
        let result = try parser.parse(["init", "--product", "framework", "--platform", "ios"])
        try subject.run(with: result)
        let temporaryPath = try self.temporaryPath()

        let name = temporaryPath.basename
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: ".gitignore")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Project.swift")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "TuistConfig.swift")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Setup.swift")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Info.plist")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Tests.plist")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(RelativePath("Sources/\(name).swift"))))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(RelativePath("Tests/\(name)Tests.swift"))))
        XCTAssertPrinterOutputContains("Project generated at path \(temporaryPath.pathString).")

        let playgroundsPath = temporaryPath.appending(component: "Playgrounds")
        XCTAssertTrue(FileHandler.shared.exists(playgroundsPath))
        XCTAssertEqual(playgroundGenerator.generateCallCount, 1)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.0, playgroundsPath)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.1, name)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.2, .iOS)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.3, PlaygroundGenerator.defaultContent())
    }

    func test_run_when_tvos_framework() throws {
        let result = try parser.parse(["init", "--product", "framework", "--platform", "tvos"])
        try subject.run(with: result)
        let temporaryPath = try self.temporaryPath()
        let name = temporaryPath.basename

        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: ".gitignore")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Project.swift")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "TuistConfig.swift")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Setup.swift")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Info.plist")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Tests.plist")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(RelativePath("Sources/\(name).swift"))))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(RelativePath("Tests/\(name)Tests.swift"))))
        XCTAssertPrinterOutputContains("Project generated at path \(temporaryPath.pathString).")

        let playgroundsPath = temporaryPath.appending(component: "Playgrounds")
        XCTAssertTrue(FileHandler.shared.exists(playgroundsPath))
        XCTAssertEqual(playgroundGenerator.generateCallCount, 1)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.0, playgroundsPath)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.1, name)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.2, .tvOS)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.3, PlaygroundGenerator.defaultContent())
    }

    func test_run_when_macos_framework() throws {
        let result = try parser.parse(["init", "--product", "framework", "--platform", "macos"])
        try subject.run(with: result)
        let temporaryPath = try self.temporaryPath()
        let name = temporaryPath.basename

        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: ".gitignore")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Project.swift")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "TuistConfig.swift")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Setup.swift")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Info.plist")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(component: "Tests.plist")))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(RelativePath("Sources/\(name).swift"))))
        XCTAssertTrue(FileHandler.shared.exists(temporaryPath.appending(RelativePath("Tests/\(name)Tests.swift"))))
        XCTAssertPrinterOutputContains("Project generated at path \(temporaryPath.pathString).")

        let playgroundsPath = temporaryPath.appending(component: "Playgrounds")
        XCTAssertTrue(FileHandler.shared.exists(playgroundsPath))
        XCTAssertEqual(playgroundGenerator.generateCallCount, 1)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.0, playgroundsPath)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.1, name)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.2, .macOS)
        XCTAssertEqual(playgroundGenerator.generateArgs.first?.3, PlaygroundGenerator.defaultContent())
    }
}
