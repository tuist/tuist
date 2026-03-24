import FileSystemTesting
import Foundation
import Testing
import TuistCore
import TuistSupport

@testable import TuistTesting

struct XcodeBuildTargetTests {
    @Test(.inTemporaryDirectory) func xcodebuildArguments_returns_the_right_arguments_when_project() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let xcodeprojPath = path.appending(component: "Project.xcodeproj")
        let subject = XcodeBuildTarget.project(xcodeprojPath)

        // When
        let got = subject.xcodebuildArguments

        // Then
        #expect(got == ["-project", xcodeprojPath.pathString])
    }

    @Test(.inTemporaryDirectory) func xcodebuildArguments_returns_the_right_arguments_when_workspace() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let xcworkspacePath = path.appending(component: "Project.xcworkspace")
        let subject = XcodeBuildTarget.workspace(xcworkspacePath)

        // When
        let got = subject.xcodebuildArguments

        // Then
        #expect(got == ["-workspace", xcworkspacePath.pathString])
    }
}
