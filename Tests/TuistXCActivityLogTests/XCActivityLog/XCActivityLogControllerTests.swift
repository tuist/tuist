import FileSystem
import Path
import Testing
import TuistSupport
@testable import TuistSupportTesting

struct XCActivityLogControllerTests {
    let subject: XCActivityLogController

    init() throws {
        subject = try XCActivityLogController(
            fileSystem: FileSystem(),
            environment: MockEnvironment()
        )
    }

    @Test func buildTimesByTarget() async throws {
        // Given
        let projectDerivedDataDirectory = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../../Fixtures/FrameworkDerivedDataWithActivityLog"))

        // When
        let got = try await subject.buildTimesByTarget(projectDerivedDataDirectory: projectDerivedDataDirectory)

        // Then
        #expect(got == ["Framework": 0.004696011543273926])
    }

    @Test func parseCleanBuildXCActivityLog() async throws {
        // Given
        let cleanBuildXCActivityLog = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../../Fixtures/clean-build.xcactivitylog"))

        // When
        let got = try subject.parse(cleanBuildXCActivityLog)

        // Then
        #expect(got.category == .clean)
    }

    @Test func parseIncrementalBuildXCActivityLog() async throws {
        // Given
        let incrementalBuildXCActivityLog = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../../Fixtures/incremental-build.xcactivitylog"))

        // When
        let got = try subject.parse(incrementalBuildXCActivityLog)

        // Then
        #expect(got.category == .incremental)
    }
}
