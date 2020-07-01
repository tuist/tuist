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

final class MockFocusServiceProjectGeneratorProvider: FocusServiceProjectGeneratorProviding {

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

final class FocusServiceTests: TuistUnitTestCase {
    var subject: FocusService!
    var opener: MockOpener!
    var generator: MockProjectGenerator!
    var generatorProvider: MockFocusServiceProjectGeneratorProvider!
    
    override func setUp() {
        super.setUp()
        opener = MockOpener()
        generator = MockProjectGenerator()
        generatorProvider = MockFocusServiceProjectGeneratorProvider()
        generatorProvider.stubbedGeneratorResult = generator
        subject = FocusService(opener: opener, generatorProvider: generatorProvider)
    }

    override func tearDown() {
        opener = nil
        generator = nil
        subject = nil
        generatorProvider = nil
        super.tearDown()
    }

    func test_run_fatalErrors_when_theworkspaceGenerationFails() throws {
        let error = NSError.test()
        generator.stubbedGenerateProjectWorkspaceError = error

        XCTAssertThrowsError(try subject.run(cache: false)) {
            XCTAssertEqual($0 as NSError?, error)
        }
    }

    func test_run() throws {
        let workspacePath = AbsolutePath("/test.xcworkspace")
        
        generator.stubbedGenerateProjectWorkspaceResult = (workspacePath, .test())
        try subject.run(cache: false)

        XCTAssertEqual(opener.openArgs.last?.0, workspacePath.pathString)
    }
}
