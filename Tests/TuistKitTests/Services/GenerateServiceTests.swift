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

final class MockGenerateServiceProjectGeneratorFactory: GenerateServiceProjectGeneratorFactorying {
    var invokedGenerator = false
    var invokedGeneratorCount = 0
    var invokedGeneratorParameters: (cache: Bool, Void)?
    var invokedGeneratorParametersList = [(cache: Bool, Void)]()
    var stubbedGeneratorResult: ProjectGenerating!

    func generator(cache: Bool) -> ProjectGenerating {
        invokedGenerator = true
        invokedGeneratorCount += 1
        invokedGeneratorParameters = (cache, ())
        invokedGeneratorParametersList.append((cache, ()))
        return stubbedGeneratorResult
    }
}

final class GenerateServiceTests: TuistUnitTestCase {
    var subject: GenerateService!
    var generator: MockProjectGenerator!
    var clock: StubClock!
    var projectGeneratorFactory: MockGenerateServiceProjectGeneratorFactory!

    override func setUp() {
        super.setUp()
        projectGeneratorFactory = MockGenerateServiceProjectGeneratorFactory()
        generator = MockProjectGenerator()
        projectGeneratorFactory.stubbedGeneratorResult = generator
        clock = StubClock()
        generator.generateStub = { _, _ in
            AbsolutePath("/Test")
        }

        subject = GenerateService(clock: clock,
                                  projectGeneratorFactory: projectGeneratorFactory)
    }

    override func tearDown() {
        projectGeneratorFactory = nil
        generator = nil
        clock = nil
        subject = nil
        super.tearDown()
    }

    func test_run() throws {
        // When
        try subject.testRun()

        // Then
        XCTAssertPrinterOutputContains("Project generated.")
    }

    func test_run_timeIsPrinted() throws {
        // Given
        clock.assertOnUnexpectedCalls = true
        clock.primedTimers = [
            0.234,
        ]

        // When
        try subject.testRun()

        // Then
        XCTAssertPrinterOutputContains("Total time taken: 0.234s")
    }

    func test_run_withRelativePathParameter() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        var generationPath: AbsolutePath?
        generator.generateStub = { path, _ in
            generationPath = path
            return path.appending(component: "Project.xcworkpsace")
        }

        // When
        try subject.testRun(path: "subpath")

        // Then
        XCTAssertEqual(generationPath, AbsolutePath("subpath", relativeTo: temporaryPath))
    }

    func test_run_withAbsoultePathParameter() throws {
        // Given
        var generationPath: AbsolutePath?
        generator.generateStub = { path, _ in
            generationPath = path
            return path.appending(component: "Project.xcworkpsace")
        }

        // When
        try subject.testRun(path: "/some/path")

        // Then
        XCTAssertEqual(generationPath, AbsolutePath("/some/path"))
    }

    func test_run_withoutPathParameter() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        var generationPath: AbsolutePath?
        generator.generateStub = { path, _ in
            generationPath = path
            return path.appending(component: "Project.xcworkpsace")
        }

        // When
        try subject.testRun()

        // Then
        XCTAssertEqual(generationPath, temporaryPath)
    }

    func test_run_withProjectOnlyParameter() throws {
        // Given
        let projectOnlyValues = [true, false]

        // When
        try projectOnlyValues.forEach {
            try subject.testRun(projectOnly: $0)
        }

        // Then
        XCTAssertEqual(generator.generateCalls.map(\.projectOnly), [
            true,
            false,
        ])
    }

    func test_run_fatalErrors_when_theworkspaceGenerationFails() throws {
        // Given
        let error = NSError.test()
        generator.generateStub = { _, _ in
            throw error
        }

        // When / Then
        XCTAssertThrowsError(try subject.testRun()) {
            XCTAssertEqual($0 as NSError, error)
        }
    }
}

extension GenerateService {
    func testRun(path: String? = nil,
                 projectOnly: Bool = false,
                 cache: Bool = false) throws
    {
        try run(path: path,
                projectOnly: projectOnly,
                cache: cache)
    }
}
