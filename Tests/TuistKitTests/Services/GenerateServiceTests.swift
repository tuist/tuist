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

private typealias GeneratorParameters = (
    sources: Set<String>,
    cacheOutputType: CacheOutputType,
    cacheProfile: TuistGraph.Cache.Profile,
    ignoreCache: Bool
)

final class GenerateServiceTests: TuistUnitTestCase {
    var subject: GenerateService!
    var opener: MockOpener!
    var generator: MockGenerator!
    var generatorFactory: MockGeneratorFactory!
    var clock: StubClock!

    override func setUp() {
        super.setUp()
        opener = MockOpener()
        generator = MockGenerator()
        generatorFactory = MockGeneratorFactory()
        generatorFactory.stubbedFocusResult = generator
        clock = StubClock()
        subject = GenerateService(clock: clock, opener: opener, generatorFactory: generatorFactory)
    }

    override func tearDown() {
        opener = nil
        generator = nil
        subject = nil
        generatorFactory = nil
        clock = nil
        super.tearDown()
    }

    func test_run_fatalErrors_when_theworkspaceGenerationFails() async throws {
        let expectedError = NSError.test()
        generator.generateStub = { _ in
            throw expectedError
        }

        do {
            try await subject
                .run(
                    path: nil,
                    sources: ["Target"],
                    noOpen: true,
                    xcframeworks: false,
                    destination: [],
                    profile: nil,
                    ignoreCache: false
                )
            XCTFail("Must throw")
        } catch {
            XCTAssertEqual(error as NSError?, expectedError)
        }
    }

    func test_run() async throws {
        let workspacePath = try AbsolutePath(validating: "/test.xcworkspace")

        generator.generateStub = { _ in
            workspacePath
        }

        try await subject.run(
            path: nil,
            sources: ["Target"],
            noOpen: false,
            xcframeworks: false,
            destination: [],
            profile: nil,
            ignoreCache: false
        )

        XCTAssertEqual(opener.openArgs.last?.0, workspacePath.pathString)
    }

    func test_run_timeIsPrinted() async throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/test.xcworkspace")

        generator.generateStub = { _ in
            workspacePath
        }
        clock.assertOnUnexpectedCalls = true
        clock.primedTimers = [
            0.234,
        ]

        // When
        try await subject.run(
            path: nil,
            sources: ["Target"],
            noOpen: false,
            xcframeworks: false,
            destination: [],
            profile: nil,
            ignoreCache: false
        )

        // Then
        XCTAssertPrinterOutputContains("Total time taken: 0.234s")
    }
}
