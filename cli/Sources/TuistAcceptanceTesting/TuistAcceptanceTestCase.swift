import FileSystem

// swiftlint:disable force_try
import Path
import TuistCore
@_exported import TuistKit
import XcodeProj
import XCTest

@testable import TuistSupport
@testable import TuistTesting

public enum Destination {
    case simulator, device
}

open class TuistAcceptanceTestCase: XCTestCase {
    public var xcodeprojPath: AbsolutePath!
    public var workspacePath: AbsolutePath!
    public var fixturePath: AbsolutePath!
    public var derivedDataPath: AbsolutePath { derivedDataDirectory.path }
    public var environment: MockEnvironment!
    public var sourceRootPath: AbsolutePath!
    public var fileSystem: FileSysteming!

    private var derivedDataDirectory: TemporaryDirectory!
    private var fixtureTemporaryDirectory: TemporaryDirectory!

    override open func setUp() async throws {
        try await super.setUp()

        fileSystem = FileSystem()

        derivedDataDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        fixtureTemporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)

        sourceRootPath = try AbsolutePath(
            validating: Environment.current.variables[
                "TUIST_CONFIG_SRCROOT"
            ]!
        )
    }

    override open func tearDown() async throws {
        fileSystem = nil
        xcodeprojPath = nil
        workspacePath = nil
        fixturePath = nil
        fixtureTemporaryDirectory = nil
        derivedDataDirectory = nil

        try await super.tearDown()
    }

    public func setUpFixture(_ fixture: String) async throws {
        let fixturesPath = sourceRootPath
            .appending(components: ["examples", "xcode"])

        fixturePath = fixtureTemporaryDirectory.path.appending(component: fixture)

        try await fileSystem.copy(
            fixturesPath.appending(component: fixture),
            to: fixturePath
        )
    }

    public func run(_ command: (some AsyncParsableCommand).Type, _ arguments: [String] = []) async throws {
        let arguments = [
            "--path", fixturePath.pathString,
        ] + arguments

        var parsedCommand = try command.parse(arguments)
        try await parsedCommand.run()
    }

    public func run(_ command: InitCommand.Type, _ arguments: String...) async throws {
        let parsedCommand = try command.parse(arguments)
        try await parsedCommand.run()
    }

    public func run(_ command: RunCommand.Type, _ arguments: String...) async throws {
        try await run(command, arguments)
    }

    public func run(_ command: RunCommand.Type, _ arguments: [String] = []) async throws {
        let arguments = [
            "--path", fixturePath.pathString,
        ] + arguments

        let parsedCommand = try command.parse(arguments)
        try await parsedCommand.run()
    }

    public func run(_ command: EditCommand.Type, _ arguments: String...) async throws {
        try await run(command, arguments)
    }

    public func run(_ command: EditCommand.Type, _ arguments: [String] = []) async throws {
        let arguments = [
            "--path", fixturePath.pathString,
            "--permanent",
        ] + arguments

        let parsedCommand = try command.parse(arguments)
        try await parsedCommand.run()

        xcodeprojPath = try FileHandler.shared.contentsOfDirectory(fixturePath)
            .first(where: { $0.basename == "Manifests.xcodeproj" })
        workspacePath = try FileHandler.shared.contentsOfDirectory(fixturePath)
            .first(where: { $0.basename == "Manifests.xcworkspace" })
    }

    public func run(_ command: MigrationTargetsByDependenciesCommand.Type, _ arguments: String...) async throws {
        try await run(command, arguments)
    }

    public func run(_ command: MigrationTargetsByDependenciesCommand.Type, _ arguments: [String] = []) async throws {
        let parsedCommand = try command.parse(arguments)
        try await parsedCommand.run()
    }

    public func run(_ command: TestCommand.Type, _ arguments: [String] = []) async throws {
        let arguments = [
            "--derived-data-path", derivedDataPath.pathString,
            "--path", fixturePath.pathString,
        ] + arguments

        let parsedCommand = try command.parse(arguments)
        try await parsedCommand.run()
    }

    public func run(_ command: BuildCommand.Type, _ arguments: [String] = []) async throws {
        let terminatorIndex = arguments.firstIndex(of: "--") ?? arguments.endIndex
        let regularArguments = arguments.prefix(upTo: terminatorIndex)
        let arguments = regularArguments + [
            "--derived-data-path", derivedDataPath.pathString,
            "--path", fixturePath.pathString,
        ] + arguments.suffix(from: terminatorIndex)

        let parsedCommand = try command.parse(Array(arguments))
        try await parsedCommand.run()
    }

    public func run(_ command: BuildCommand.Type, _ arguments: String...) async throws {
        try await run(command, arguments)
    }

    public func run(_ command: ShareCommand.Type, _ arguments: [String] = []) async throws {
        let arguments = [
            "--derived-data-path", derivedDataPath.pathString,
            "--path", fixturePath.pathString,
        ] + arguments

        let parsedCommand = try command.parse(arguments)
        try await parsedCommand.run()
    }

    public func run(_ command: ShareCommand.Type, _ arguments: String...) async throws {
        try await run(command, arguments)
    }

    public func run(_ command: GenerateCommand.Type, _ arguments: String...) async throws {
        try await run(command, arguments)
    }

    public func run(_ command: GenerateCommand.Type, _ arguments: [String] = []) async throws {
        let arguments = [
            "--no-open",
            "--path", fixturePath.pathString,
        ] + arguments

        let parsedCommand = try command.parse(arguments)
        try await parsedCommand.run()

        xcodeprojPath = try FileHandler.shared.contentsOfDirectory(fixturePath)
            .first(where: { $0.extension == "xcodeproj" })
        workspacePath = try FileHandler.shared.contentsOfDirectory(fixturePath)
            .first(where: { $0.extension == "xcworkspace" })
    }

    public func run(_ command: XcodeBuildBuildCommand.Type, _ arguments: String...) async throws {
        try await run(command, arguments)
    }

    public func run(_ command: XcodeBuildBuildCommand.Type, _ arguments: [String] = []) async throws {
        let parsedCommand = try command.parse(arguments)
        try await parsedCommand.run()
    }

    public func run(_ command: XcodeBuildTestCommand.Type, _ arguments: String...) async throws {
        try await run(command, arguments)
    }

    public func run(_ command: XcodeBuildTestCommand.Type, _ arguments: [String] = []) async throws {
        let parsedCommand = try command.parse(arguments)
        try await parsedCommand.run()
    }

    public func run(_ command: (some AsyncParsableCommand).Type, _ arguments: String...) async throws {
        try await run(command, Array(arguments))
    }

    public func run(_ command: (some ParsableCommand).Type, _ arguments: [String] = []) throws {
        var parsedCommand = try command.parseAsRoot(
            arguments +
                ["--path", fixturePath.pathString]
        )
        try parsedCommand.run()
    }

    public func run(_ command: (some ParsableCommand).Type, _ arguments: String...) throws {
        try run(command, Array(arguments))
    }

    public func addEmptyLine(to file: String) throws {
        let filePath = try fixturePath.appending(RelativePath(validating: file))
        var contents = try FileHandler.shared.readTextFile(filePath)
        contents += "\n"
        try FileHandler.shared.write(contents, path: filePath, atomically: true)
    }

    public func XCTAssertXCFrameworkLinked(
        _ framework: String,
        by targetName: String,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)
        let target = try XCTUnwrapTarget(targetName, in: xcodeproj)

        guard try target.frameworksBuildPhase()?.files?
            .contains(where: { $0.file?.nameOrPath == "\(framework).xcframework" }) == true
        else {
            XCTFail(
                "Target \(targetName) doesn't link the xcframework \(framework)",
                file: file,
                line: line
            )
            return
        }
    }

    public func XCTAssertXCFrameworkNotLinked(
        _ framework: String,
        by targetName: String,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)
        let target = try XCTUnwrapTarget(targetName, in: xcodeproj)

        if try target.frameworksBuildPhase()?.files?
            .contains(where: { $0.file?.nameOrPath == "\(framework).xcframework" }) == true
        {
            XCTFail(
                "Target \(targetName) links the xcframework \(framework)",
                file: file,
                line: line
            )
            return
        }
    }
}

// swiftlint:enable force_try
