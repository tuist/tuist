import Foundation
import TSCBasic
import TuistCore
import TuistLoader
import TuistSupport
import XcodeProj
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class GenerateServiceTests: TuistUnitTestCase {
    var subject: GenerateService!
    var generator: MockGenerator!
    var opener: MockOpener!
    var clock: StubClock!
    var generatorFactory: MockGeneratorFactory!

    override func setUp() {
        super.setUp()
        opener = MockOpener()
        generatorFactory = MockGeneratorFactory()
        generator = MockGenerator()
        generatorFactory.stubbedDefaultResult = generator
        clock = StubClock()
        generator.generateStub = { _, _ in
            AbsolutePath("/Test")
        }

        subject = GenerateService(
            clock: clock,
            opener: opener,
            generatorFactory: generatorFactory
        )
    }

    override func tearDown() {
        generatorFactory = nil
        generator = nil
        clock = nil
        subject = nil
        opener = nil
        super.tearDown()
    }

    func test_run() async throws {
        // When
        try await subject.testRun()

        // Then
        XCTAssertEqual(opener.openCallCount, 0)
        XCTAssertPrinterOutputContains("Project generated.")
    }

    func test_run_opens_the_project_when_open_is_true() async throws {
        // When
        try await subject.testRun(open: true)

        // Then
        XCTAssertEqual(opener.openCallCount, 1)
    }

    func test_run_timeIsPrinted() async throws {
        // Given
        clock.assertOnUnexpectedCalls = true
        clock.primedTimers = [
            0.234,
        ]

        // When
        try await subject.testRun()

        // Then
        XCTAssertPrinterOutputContains("Total time taken: 0.234s")
    }

    func test_run_withRelativePathParameter() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        var generationPath: AbsolutePath?
        generator.generateStub = { path, _ in
            generationPath = path
            return path.appending(component: "Project.xcworkpsace")
        }

        // When
        try await subject.testRun(path: "subpath")

        // Then
        XCTAssertEqual(generationPath, AbsolutePath("subpath", relativeTo: temporaryPath))
    }

    func test_run_withAbsoultePathParameter() async throws {
        // Given
        var generationPath: AbsolutePath?
        generator.generateStub = { path, _ in
            generationPath = path
            return path.appending(component: "Project.xcworkpsace")
        }

        // When
        try await subject.testRun(path: "/some/path")

        // Then
        XCTAssertEqual(generationPath, AbsolutePath("/some/path"))
    }

    func test_run_withoutPathParameter() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        var generationPath: AbsolutePath?
        generator.generateStub = { path, _ in
            generationPath = path
            return path.appending(component: "Project.xcworkpsace")
        }

        // When
        try await subject.testRun()

        // Then
        XCTAssertEqual(generationPath, temporaryPath)
    }

    func test_run_withProjectOnlyParameter() async throws {
        // Given
        let projectOnlyValues = [true, false]

        // When
        for isProjectOnly in projectOnlyValues {
            try await subject.testRun(projectOnly: isProjectOnly)
        }

        // Then
        XCTAssertEqual(generator.generateCalls.map(\.projectOnly), [
            true,
            false,
        ])
    }

    func test_run_fatalErrors_when_theworkspaceGenerationFails() async throws {
        // Given
        let expectedError = NSError.test()
        generator.generateStub = { _, _ in
            throw expectedError
        }

        // When / Then
        do {
            try await subject.testRun()
            XCTFail("Should throw")
        } catch {
            XCTAssertEqual(error as NSError, expectedError)
        }
    }
}

extension GenerateService {
    func testRun(path: String? = nil,
                 projectOnly: Bool = false,
                 open: Bool = false) async throws
    {
        try await run(
            path: path,
            projectOnly: projectOnly,
            open: open
        )
    }
}
