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

    func test_pathArgument() {
        XCTAssertEqual(subject.pathArgument.shortName, "-p")
        XCTAssertEqual(subject.pathArgument.usage, "The path where the Project.swift file will be generated")
        XCTAssertEqual(subject.pathArgument.completion, ShellCompletion.filename)
    }

    func test_command() throws {
        let tmpDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        try "".write(toFile: tmpDir.path.appending(component: "Info.plist").asString, atomically: true, encoding: .utf8)
        try "".write(toFile: tmpDir.path.appending(component: "Debug.xcconfig").asString, atomically: true, encoding: .utf8)
        let result = try parser.parse([InitCommand.command, "-p", tmpDir.path.asString])
        try subject.run(with: result)
        let project = try Project.at(tmpDir.path, context: graphLoaderContext)
        XCTAssertEqual(project.name, tmpDir.path.components.last)
        XCTAssertEqual(project.schemes.count, 1)
        XCTAssertEqual(project.targets.first?.name, tmpDir.path.components.last)
        XCTAssertEqual(project.targets.first?.platform, .iOS)
        XCTAssertEqual(project.targets.first?.product, .app)
        XCTAssertEqual(project.targets.first?.bundleId, "com.xcodepm.\(tmpDir.path.components.last!)")
        XCTAssertEqual(project.targets.first?.dependencies.count, 0)
        XCTAssertNil(project.targets.first?.settings)
        XCTAssertEqual(project.targets.first?.buildPhases.count, 1)
    }
}
