import FileSystemTesting
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

        // When
        let got = try #require(subject.parse(path: xcresult, rootDirectory: nil))

        // Then
        let tests = got.testSummaries.flatMap(\.summaries).flatMap(\.testableSummaries).flatMap(\.tests).flatMap(\.subtests)
        #expect(tests.filter(\.isSuccessful).count == 2)
        #expect(tests.filter { $0.isSuccessful == false }.count == 1)
    }
}
