import FileSystem
import Path
import Testing
import TuistSupport

@testable import TuistTesting
@testable import TuistXCActivityLog

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
        let got = try await subject.parse(cleanBuildXCActivityLog)

        // Then
        #expect(got.category == .clean)
    }

    @Test func parseIncrementalBuildXCActivityLog() async throws {
        // Given
        let incrementalBuildXCActivityLog = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../../Fixtures/incremental-build.xcactivitylog"))

        // When
        let got = try await subject.parse(incrementalBuildXCActivityLog)

        // Then
        #expect(got.category == .incremental)
    }

    @Test func parseFailedBuildXCActivityLog() async throws {
        // Given
        let xcactivityLog = try AbsolutePath(validating: #file).parentDirectory
            .appending(try RelativePath(validating: "../../Fixtures/failed-build.xcactivitylog"))

        // When
        let got = try await subject.parse(xcactivityLog)

        // Then
        #expect(got.issues.map(\.type) == [.error])
        let issue = try #require(got.issues.first)
        #expect(issue.target == "Framework1")
        #expect(issue.project == "MainApp")
        #expect(issue.title == "Compile Framework1File.swift (arm64)")
        print(got.files.map(\.path))
        let files = got.files.sorted(by: { $0.path.pathString < $1.path.pathString })
        #expect(
            files.map(\.path.pathString) == [
                "Framework1/Sources/Framework1File.swift",
                "Framework2/Sources/Framework2File.swift",
                "Framework3/Sources/Framework3File.swift",
                "Framework4/Sources/Framework4File.swift",
                "Framework5/Sources/Framework5File.swift",
            ]
        )
        let targets = got.targets.sorted(by: { $0.name < $1.name })
        #expect(targets.map(\.name) == ["Framework1", "Framework2-iOS", "Framework3", "Framework4", "Framework5"])
        #expect(targets.map(\.status) == [.failure, .success, .success, .success, .success])
    }
}
