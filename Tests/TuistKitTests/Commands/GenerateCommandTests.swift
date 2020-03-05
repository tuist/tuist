import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistLoader
import TuistSupport
import XcodeProj
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class GenerateCommandTests: TuistUnitTestCase {
    var subject: GenerateCommand!
    var generator: MockGenerator!
    var parser: ArgumentParser!
    var manifestLoader: MockManifestLoader!
    var clock: StubClock!

    override func setUp() {
        super.setUp()
        generator = MockGenerator()
        parser = ArgumentParser.test()
        manifestLoader = MockManifestLoader()
        clock = StubClock()

        subject = GenerateCommand(parser: parser,
                                  generator: generator,
                                  manifestLoader: manifestLoader,
                                  clock: clock)
    }

    override func tearDown() {
        generator = nil
        parser = nil
        manifestLoader = nil
        clock = nil
        subject = nil
        super.tearDown()
    }

    func test_command() {
        XCTAssertEqual(GenerateCommand.command, "generate")
    }

    func test_overview() {
        XCTAssertEqual(GenerateCommand.overview, "Generates an Xcode workspace to start working on the project.")
    }

    func test_run_withProjectManifestPrints() throws {
        // Given
        let result = try parser.parse([GenerateCommand.command])
        manifestLoader.manifestsAtStub = { _ in
            Set([.project])
        }

        // When
        try subject.run(with: result)

        // Then
        XCTAssertPrinterOutputContains("Project generated.")
    }

    func test_run_withWorkspacetManifestPrints() throws {
        // Given
        let result = try parser.parse([GenerateCommand.command])
        manifestLoader.manifestsAtStub = { _ in
            Set([.workspace])
        }

        // When
        try subject.run(with: result)

        // Then
        XCTAssertPrinterOutputContains("Project generated.")
    }

    func test_run_timeIsPrinted() throws {
        // Given
        let result = try parser.parse([GenerateCommand.command])
        manifestLoader.manifestsAtStub = { _ in
            Set([.project])
        }
        clock.assertOnUnexpectedCalls = true
        clock.primedTimers = [
            0.234,
        ]

        // When
        try subject.run(with: result)

        // Then
        XCTAssertPrinterOutputContains("Total time taken: 0.234s")
    }

    func test_run_withRelativePathParameter() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let graph = Graph.test()
        let result = try parser.parse([GenerateCommand.command, "--path", "subpath"])
        var generationPath: AbsolutePath?
        manifestLoader.manifestsAtStub = { _ in
            Set([.project])
        }
        generator.generateProjectWorkspaceStub = { path, _ in
            generationPath = path
            return (path.appending(component: "project.xcworkspace"), graph)
        }

        // When
        try subject.run(with: result)

        // Then
        XCTAssertEqual(generationPath, AbsolutePath("subpath", relativeTo: temporaryPath))
    }

    func test_run_withAbsoultePathParameter() throws {
        // Given
        let result = try parser.parse([GenerateCommand.command, "--path", "/some/path"])
        let graph = Graph.test()
        var generationPath: AbsolutePath?
        manifestLoader.manifestsAtStub = { _ in
            Set([.project])
        }
        generator.generateProjectWorkspaceStub = { path, _ in
            generationPath = path
            return (path.appending(component: "project.xcworkspace"), graph)
        }

        // When
        try subject.run(with: result)

        // Then
        XCTAssertEqual(generationPath, AbsolutePath("/some/path"))
    }

    func test_run_withoutPathParameter() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let graph = Graph.test()
        let result = try parser.parse([GenerateCommand.command])
        var generationPath: AbsolutePath?
        manifestLoader.manifestsAtStub = { _ in
            Set([.project])
        }
        generator.generateProjectWorkspaceStub = { path, _ in
            generationPath = path
            return (path.appending(component: "project.xcworkspace"), graph)
        }

        // When
        try subject.run(with: result)

        // Then
        XCTAssertEqual(generationPath, temporaryPath)
    }

    func test_run_withProjectOnlyParameter() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let graph = Graph.test()
        let result = try parser.parse([GenerateCommand.command, "--project-only"])
        var generationPath: AbsolutePath?
        manifestLoader.manifestsAtStub = { _ in
            Set([.project])
        }
        generator.generateProjectAtStub = { path in
            generationPath = path
            return (path.appending(component: "project.xcodeproj"), graph)
        }

        // When
        try subject.run(with: result)

        // Then
        XCTAssertEqual(generationPath, temporaryPath)
    }

    func test_run_withMissingManifest_throws() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let result = try parser.parse([GenerateCommand.command])
        manifestLoader.manifestsAtStub = { _ in
            Set()
        }

        // When / Then
        XCTAssertThrowsSpecific(try subject.run(with: result),
                                ManifestLoaderError.manifestNotFound(temporaryPath))
    }

    func test_run_fatalErrors_when_theworkspaceGenerationFails() throws {
        // Given
        let result = try parser.parse([GenerateCommand.command])
        let error = NSError.test()
        manifestLoader.manifestsAtStub = { _ in
            Set([.project])
        }
        generator.generateProjectWorkspaceStub = { _, _ in
            throw error
        }

        // When / Then
        XCTAssertThrowsError(try subject.run(with: result)) {
            XCTAssertEqual($0 as NSError, error)
        }
    }
}
