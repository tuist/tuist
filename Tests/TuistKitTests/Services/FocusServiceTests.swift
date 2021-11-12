import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistLoader
import XcodeProj
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class MockFocusServiceProjectGeneratorFactory: FocusServiceProjectGeneratorFactorying {
    struct GeneratorParameters: Equatable {
        let sources: Set<String>
        let xcframeworks: Bool
        let cacheProfile: TuistGraph.Cache.Profile
        let ignoreCache: Bool
    }

    var invokedGenerator = false
    var invokedGeneratorCount = 0
    var invokedGeneratorParameters: GeneratorParameters?
    var invokedGeneratorParametersList = [GeneratorParameters]()
    var stubbedGeneratorResult: Generating!

    func generator(sources: Set<String>, xcframeworks: Bool, cacheProfile: TuistGraph.Cache.Profile, ignoreCache: Bool) -> Generating {
        invokedGenerator = true
        invokedGeneratorCount += 1
        let generatorParameters = GeneratorParameters(
            sources: sources,
            xcframeworks: xcframeworks,
            cacheProfile: cacheProfile,
            ignoreCache: ignoreCache
        )
        invokedGeneratorParameters = generatorParameters
        invokedGeneratorParametersList.append(generatorParameters)
        return stubbedGeneratorResult
    }
}

final class FocusServiceTests: TuistUnitTestCase {
    var subject: FocusService!
    var opener: MockOpener!
    var generator: MockGenerator!
    var generatorFactory: MockGeneratorFactory!

    override func setUp() {
        super.setUp()
        opener = MockOpener()
        generator = MockGenerator()
        generatorFactory = MockGeneratorFactory()
        generatorFactory.stubbedFocusResult = generator
        subject = FocusService(opener: opener, generatorFactory: generatorFactory)
    }

    override func tearDown() {
        opener = nil
        generator = nil
        subject = nil
        generatorFactory = nil
        super.tearDown()
    }

    func test_run_fatalErrors_when_theworkspaceGenerationFails() throws {
        let error = NSError.test()
        generator.generateStub = { _, _ in
            throw error
        }

        XCTAssertThrowsError(try subject.run(path: nil, sources: Set(), noOpen: true, xcframeworks: false, profile: nil, ignoreCache: false)) {
            XCTAssertEqual($0 as NSError?, error)
        }
    }

    func test_run() throws {
        let workspacePath = AbsolutePath("/test.xcworkspace")

        generator.generateStub = { _, _ in
            workspacePath
        }

        try subject.run(path: nil, sources: Set(), noOpen: false, xcframeworks: false, profile: nil, ignoreCache: false)

        XCTAssertEqual(opener.openArgs.last?.0, workspacePath.pathString)
    }
}
