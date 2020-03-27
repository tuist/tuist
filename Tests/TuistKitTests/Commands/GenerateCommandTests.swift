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
    var generator: MockProjectGenerator!
    var parser: ArgumentParser!
    var clock: StubClock!

    override func setUp() {
        super.setUp()
        generator = MockProjectGenerator()
        parser = ArgumentParser.test()
        clock = StubClock()
        generator.generateStub = { _, _ in
            AbsolutePath("/Test")
        }

        subject = GenerateCommand(parser: parser,
                                  generator: generator,
                                  clock: clock)
    }

    override func tearDown() {
        generator = nil
        parser = nil
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

    func test_run() throws {
        // Given
        let result = try parser.parse([GenerateCommand.command])

        // When
        try subject.run(with: result)

        // Then
        XCTAssertPrinterOutputContains("Project generated.")
    }

    func test_run_timeIsPrinted() throws {
        // Given
        let result = try parser.parse([GenerateCommand.command])
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
        let result = try parser.parse([GenerateCommand.command, "--path", "subpath"])
        var generationPath: AbsolutePath?
        generator.generateStub = { path, _ in
            generationPath = path
            return path.appending(component: "Project.xcworkpsace")
        }

        // When
        try subject.run(with: result)

        // Then
        XCTAssertEqual(generationPath, AbsolutePath("subpath", relativeTo: temporaryPath))
    }

    func test_run_withAbsoultePathParameter() throws {
        // Given
        let result = try parser.parse([GenerateCommand.command, "--path", "/some/path"])
        var generationPath: AbsolutePath?
        generator.generateStub = { path, _ in
            generationPath = path
            return path.appending(component: "Project.xcworkpsace")
        }

        // When
        try subject.run(with: result)

        // Then
        XCTAssertEqual(generationPath, AbsolutePath("/some/path"))
    }

    func test_run_withoutPathParameter() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let result = try parser.parse([GenerateCommand.command])
        var generationPath: AbsolutePath?
        generator.generateStub = { path, _ in
            generationPath = path
            return path.appending(component: "Project.xcworkpsace")
        }

        // When
        try subject.run(with: result)

        // Then
        XCTAssertEqual(generationPath, temporaryPath)
    }

    func test_run_withProjectOnlyParameter() throws {
        // Given
        let arguments = [
            [GenerateCommand.command, "--project-only"],
            [GenerateCommand.command],
        ]

        // When
        try arguments.forEach {
            let result = try parser.parse($0)
            try subject.run(with: result)
        }

        // Then
        XCTAssertEqual(generator.generateCalls.map(\.projectOnly), [
            true,
            false,
        ])
    }

    func test_run_fatalErrors_when_theworkspaceGenerationFails() throws {
        // Given
        let result = try parser.parse([GenerateCommand.command])
        let error = NSError.test()
        generator.generateStub = { _, _ in
            throw error
        }

        // When / Then
        XCTAssertThrowsError(try subject.run(with: result)) {
            XCTAssertEqual($0 as NSError, error)
        }
    }
}
