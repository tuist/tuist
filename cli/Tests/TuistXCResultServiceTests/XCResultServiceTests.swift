import FileSystemTesting
import Foundation
import Path
import Testing
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
        #expect(got.testModules.map(\.duration) == [2902])
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
}
