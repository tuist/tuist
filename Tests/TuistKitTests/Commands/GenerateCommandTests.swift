import Basic
import Foundation
import TuistCore
import Utility
import xcodeproj
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

final class GenerateCommandTests: XCTestCase {
    var subject: GenerateCommand!
    var generator: MockGenerator!
    var parser: ArgumentParser!
    var printer: MockPrinter!
    var fileHandler: MockFileHandler!
    var manifestLoader: MockGraphManifestLoader!

    override func setUp() {
        super.setUp()
        do {
            printer = MockPrinter()
            generator = MockGenerator()
            parser = ArgumentParser.test()
            fileHandler = try MockFileHandler()
            manifestLoader = MockGraphManifestLoader()

            subject = GenerateCommand(parser: parser,
                                      printer: printer,
                                      fileHandler: fileHandler,
                                      generator: generator,
                                      manifestLoader: manifestLoader)
        } catch {
            XCTFail("failed to setup test: \(error.localizedDescription)")
        }
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
        XCTAssertEqual(printer.printSuccessArgs.first, "Project generated.")
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
        XCTAssertEqual(printer.printSuccessArgs.first, "Project generated.")
    }

    func test_run_withRelativePathParameter() throws {
        // Given
        let path = fileHandler.currentPath
        let result = try parser.parse([GenerateCommand.command, "--path", "subpath"])
        var generationPath: AbsolutePath?
        manifestLoader.manifestsAtStub = { _ in
            Set([.project])
        }
        generator.generateProjectStub = { path, _, _ in
            generationPath = path
            return path.appending(component: "project.xcworkspace")
        }

        // When
        try subject.run(with: result)

        // Then
        XCTAssertEqual(generationPath, AbsolutePath("subpath", relativeTo: path))
    }

    func test_run_withAbsoultePathParameter() throws {
        // Given
        let result = try parser.parse([GenerateCommand.command, "--path", "/some/path"])
        var generationPath: AbsolutePath?
        manifestLoader.manifestsAtStub = { _ in
            Set([.project])
        }
        generator.generateProjectStub = { path, _, _ in
            generationPath = path
            return path.appending(component: "project.xcworkspace")
        }

        // When
        try subject.run(with: result)

        // Then
        XCTAssertEqual(generationPath, AbsolutePath("/some/path"))
    }

    func test_run_withoutPathParameter() throws {
        // Given
        let result = try parser.parse([GenerateCommand.command])
        var generationPath: AbsolutePath?
        manifestLoader.manifestsAtStub = { _ in
            Set([.project])
        }
        generator.generateProjectStub = { path, _, _ in
            generationPath = path
            return path.appending(component: "project.xcworkspace")
        }

        // When
        try subject.run(with: result)

        // Then
        XCTAssertEqual(generationPath, fileHandler.currentPath)
    }

    func test_run_withMissingManifest_throws() throws {
        // Given
        let path = fileHandler.currentPath
        let result = try parser.parse([GenerateCommand.command])
        manifestLoader.manifestsAtStub = { _ in
            Set()
        }

        // When / Then
        XCTAssertThrowsError(try subject.run(with: result)) {
            XCTAssertEqual($0 as? GraphManifestLoaderError, GraphManifestLoaderError.manifestNotFound(path))
        }
    }

    func test_run_fatalErrors_when_theworkspaceGenerationFails() throws {
        // Given
        let result = try parser.parse([GenerateCommand.command])
        let error = NSError.test()
        manifestLoader.manifestsAtStub = { _ in
            Set([.project])
        }
        generator.generateProjectStub = { _, _, _ in
            throw error
        }

        // When / Then
        XCTAssertThrowsError(try subject.run(with: result)) {
            XCTAssertEqual($0 as NSError, error)
        }
    }
}
