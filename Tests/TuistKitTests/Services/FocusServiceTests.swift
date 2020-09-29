import Foundation
import TSCBasic
import TuistCore
import TuistLoader
import XcodeProj
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class MockFocusServiceProjectGeneratorFactory: FocusServiceProjectGeneratorFactorying {
    var invokedGenerator = false
    var invokedGeneratorCount = 0
    var invokedGeneratorParameters: (sources: Set<String>, xcframeworks: Bool)?
    var invokedGeneratorParametersList = [(sources: Set<String>, xcframeworks: Bool)]()
    var stubbedGeneratorResult: ProjectGenerating!

    func generator(sources: Set<String>, xcframeworks: Bool) -> ProjectGenerating {
        invokedGenerator = true
        invokedGeneratorCount += 1
        invokedGeneratorParameters = (sources, xcframeworks)
        invokedGeneratorParametersList.append((sources, xcframeworks))
        return stubbedGeneratorResult
    }
}

final class FocusServiceErrorTests: TuistUnitTestCase {
    func test_description() {
        XCTAssertEqual(FocusServiceError.cacheWorkspaceNonSupported.description, "Caching is only supported when focusing on a project. Please, run the command in a directory that contains a Project.swift file.")
    }

    func test_type() {
        XCTAssertEqual(FocusServiceError.cacheWorkspaceNonSupported.type, .abort)
    }
}

final class FocusServiceTests: TuistUnitTestCase {
    var subject: FocusService!
    var opener: MockOpener!
    var generator: MockProjectGenerator!
    var projectGeneratorFactory: MockFocusServiceProjectGeneratorFactory!

    override func setUp() {
        super.setUp()
        opener = MockOpener()
        generator = MockProjectGenerator()
        projectGeneratorFactory = MockFocusServiceProjectGeneratorFactory()
        projectGeneratorFactory.stubbedGeneratorResult = generator
        subject = FocusService(opener: opener, projectGeneratorFactory: projectGeneratorFactory)
    }

    override func tearDown() {
        opener = nil
        generator = nil
        subject = nil
        projectGeneratorFactory = nil
        super.tearDown()
    }

    func test_run_fatalErrors_when_theworkspaceGenerationFails() throws {
        let error = NSError.test()
        generator.generateStub = { _, _ in
            throw error
        }

        XCTAssertThrowsError(try subject.run(path: nil, sources: Set(), noOpen: true, xcframeworks: false)) {
            XCTAssertEqual($0 as NSError?, error)
        }
    }

    func test_run() throws {
        let workspacePath = AbsolutePath("/test.xcworkspace")

        generator.generateStub = { _, _ in
            workspacePath
        }

        try subject.run(path: nil, sources: Set(), noOpen: false, xcframeworks: false)

        XCTAssertEqual(opener.openArgs.last?.0, workspacePath.pathString)
    }
}
