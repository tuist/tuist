import Foundation
import MockableTest
import TSCBasic
import TuistCore
import XcodeProjectGenerator
import TuistLoader
import TuistServer
import XcodeProj
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class GenerateServiceTests: TuistUnitTestCase {
    private var subject: GenerateService!
    private var opener: MockOpener!
    private var generator: MockGenerator!
    private var generatorFactory: MockGeneratorFactorying!
    private var cacheStorageFactory: MockCacheStorageFactorying!
    private var clock: StubClock!

    override func setUp() {
        super.setUp()
        opener = MockOpener()
        generator = MockGenerator()
        generatorFactory = .init()
        given(generatorFactory)
            .generation(
                config: .any,
                sources: .any,
                configuration: .any,
                ignoreBinaryCache: .any,
                cacheStorage: .any
            )
            .willReturn(generator)
        cacheStorageFactory = .init()
        given(cacheStorageFactory)
            .cacheStorage(config: .any)
            .willReturn(MockCacheStoring())
        clock = StubClock()
        subject = GenerateService(
            cacheStorageFactory: cacheStorageFactory,
            generatorFactory: generatorFactory,
            clock: clock,
            opener: opener
        )
    }

    override func tearDown() {
        opener = nil
        generator = nil
        subject = nil
        generatorFactory = nil
        cacheStorageFactory = nil
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
                    sources: [],
                    noOpen: true,
                    configuration: nil,
                    ignoreBinaryCache: false
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
            sources: [],
            noOpen: false,
            configuration: nil,
            ignoreBinaryCache: false
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
            sources: [],
            noOpen: false,
            configuration: nil,
            ignoreBinaryCache: false
        )

        // Then
        XCTAssertPrinterOutputContains("Total time taken: 0.234s")
    }
}
