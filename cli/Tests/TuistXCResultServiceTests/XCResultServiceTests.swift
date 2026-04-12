import FileSystemTesting
import Foundation
import Path
import Testing
import XCResultParser
@testable import TuistXCResultService

struct XCResultServiceTests {
    private let subject = XCResultService()

    @Test
    func parseTestXCResult() async throws {
        // Given
        let xcresult = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../Fixtures/test.xcresult"))
        let cet = TimeZone(identifier: "Europe/Berlin")!

        // When
        let got = try #require(await TimeZone.$current.withValue({ cet }) {
            try await subject.parse(path: xcresult, rootDirectory: nil)
        })

        // Then
        #expect(got.status == .failed)
        #expect(got.testModules.map(\.name) == ["AppTests"])
        #expect(got.testModules.map(\.duration) == [2923])
        #expect(got.testModules.map(\.status) == [.failed])
        #expect(got.testModules.flatMap(\.testSuites).map(\.duration).sorted() == [5, 104, 111])
        #expect(got.testCases.compactMap(\.duration).sorted() == [3, 4, 101, 108, 108, 110])
        #expect(got.testCases.filter { $0.status == .passed }.count == 2)
        let failedTestCases = got.testCases.filter { $0.status == .failed }.sorted(by: { $0.name > $1.name })
        #expect(failedTestCases.count == 4)
        #expect(
            failedTestCases.flatMap { $0.failures.map(\.message) } == [
                "Error Domain=com Code=1 \"(null)\"",
                "XCTAssertTrue failed",
                "true == false",
                "Error Domain=com Code=1 \"(null)\"",
            ]
        )
    }

    @Test
    func parseTestWithCustomLabelXCResult() async throws {
        // Given
        let xcresult = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../Fixtures/test-with-custom-label.xcresult"))
        let cet = TimeZone(identifier: "Europe/Berlin")!

        // When
        let got = try #require(await TimeZone.$current.withValue({ cet }) {
            try await subject.parse(path: xcresult, rootDirectory: nil)
        })

        // Then
        #expect(got.status == .passed)
        #expect(got.testCases.map(\.name) == ["Custom test label"])
        #expect(got.testCases.compactMap(\.duration).sorted() == [103])
    }

    @Test
    func parseTestWithRepetitionsXCResult() async throws {
        // Given
        let xcresult = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../Fixtures/test-with-repetitions.xcresult"))

        // When
        let got = try #require(try await subject.parse(path: xcresult, rootDirectory: nil))

        // Then
        #expect(got.status == .passed)
        #expect(got.testCases.count == 2)

        // Verify flaky test (example) - first run failed, retry passed
        print(got.testCases)
        let flakyTest = try #require(got.testCases.first { $0.name == "example()" })
        #expect(flakyTest.status == .passed)
        #expect(flakyTest.repetitions.count == 2)
        #expect(flakyTest.repetitions[0].name == "First Run")
        #expect(flakyTest.repetitions[0].status == .failed)
        #expect(flakyTest.repetitions[0].repetitionNumber == 1)
        #expect(flakyTest.repetitions[1].name == "Retry 1")
        #expect(flakyTest.repetitions[1].status == .passed)
        #expect(flakyTest.repetitions[1].repetitionNumber == 2)
        // Failure message should be captured from the failed repetition
        #expect(flakyTest.failures.count == 1)
        #expect(flakyTest.failures[0].message?.contains("Bool.random()") == true)

        // Verify non-flaky test (topLevelTest) - both runs passed
        let nonFlakyTest = try #require(got.testCases.first { $0.name == "topLevelTest()" })
        #expect(nonFlakyTest.status == .passed)
        #expect(nonFlakyTest.repetitions.count == 2)
        #expect(nonFlakyTest.repetitions[0].status == .passed)
        #expect(nonFlakyTest.repetitions[1].status == .passed)
        #expect(nonFlakyTest.failures.isEmpty)
    }

    @Test
    func parseTestWithArgumentsXCResult() async throws {
        // Given
        let xcresult = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../Fixtures/test-with-arguments.xcresult"))

        // When
        let got = try #require(try await subject.parse(path: xcresult, rootDirectory: nil))

        // Then
        #expect(got.status == .failed)

        // Find the parameterized test case
        let parameterizedTest = try #require(got.testCases.first { $0.name == "parameterized(value:)" })
        #expect(parameterizedTest.status == .failed)
        #expect(parameterizedTest.arguments.count == 3)

        // Top-level failures should be empty (failures live in arguments)
        #expect(parameterizedTest.failures.isEmpty)

        // Verify each argument variant
        let helloArg = try #require(parameterizedTest.arguments.first { $0.name.contains("hello") })
        #expect(helloArg.status == .passed)
        #expect(helloArg.failures.isEmpty)

        let testArg = try #require(parameterizedTest.arguments.first { $0.name.contains("test") })
        #expect(testArg.status == .failed)
        #expect(testArg.failures.count == 1)
        #expect(testArg.failures[0].message?.contains("Expected long string") == true)

        let worldArg = try #require(parameterizedTest.arguments.first { $0.name.contains("world") })
        #expect(worldArg.status == .passed)
        #expect(worldArg.failures.isEmpty)

        // Non-parameterized test should have no arguments
        let regularTest = try #require(got.testCases.first { $0.name == "example()" })
        #expect(regularTest.status == .passed)
        #expect(regularTest.arguments.isEmpty)
    }

    // MARK: - parseTestStatuses

    @Test
    func parseTestStatuses_returnsCorrectStatuses() async throws {
        let xcresult = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../Fixtures/test.xcresult"))

        let got = try await subject.parseTestStatuses(path: xcresult)

        #expect(got.hasFailures == true)
        let passed = got.testCases.filter { $0.status == .passed }
        let failed = got.testCases.filter { $0.status == .failed }
        #expect(passed.count == 2)
        #expect(failed.count == 4)
        #expect(got.testCases.allSatisfy { $0.module == "AppTests" })
    }

    @Test
    func parseTestStatuses_returnsPassingModuleNames() async throws {
        let xcresult = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../Fixtures/test-with-custom-label.xcresult"))

        let got = try await subject.parseTestStatuses(path: xcresult)

        #expect(got.hasFailures == false)
        #expect(got.passingModuleNames().contains("AppTests"))
    }

    @Test
    func parseTestStatuses_extractsModuleAndSuiteNames() async throws {
        let xcresult = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../Fixtures/test.xcresult"))

        let got = try await subject.parseTestStatuses(path: xcresult)

        let modules = Set(got.testCases.compactMap(\.module))
        #expect(modules == ["AppTests"])
        #expect(got.testCases.contains { $0.testSuite != nil })
    }
}
