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
        #expect(got.testModules.map(\.name) == ["AppTests"])
        #expect(got.testModules.map(\.status) == [.failed])
        #expect(got.testCases.compactMap(\.duration).sorted() == [0, 1, 2])
        #expect(got.testCases.filter { $0.status == .passed }.count == 2)
        #expect(got.testCases.filter { $0.status == .failed }.count == 1)
    }
}
