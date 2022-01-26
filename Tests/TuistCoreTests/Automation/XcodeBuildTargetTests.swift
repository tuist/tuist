import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistSupportTesting

final class XcodeBuildTargetTests: TuistUnitTestCase {
    func test_xcodebuildArguments_returns_the_right_arguments_when_project() throws {
        // Given
        let path = try temporaryPath()
        let xcodeprojPath = path.appending(component: "Project.xcodeproj")
        let subject = XcodeBuildTarget.project(xcodeprojPath)

        // When
        let got = subject.xcodebuildArguments

        // Then
        XCTAssertEqual(got, ["-project", xcodeprojPath.pathString])
    }

    func test_xcodebuildArguments_returns_the_right_arguments_when_workspace() throws {
        // Given
        let path = try temporaryPath()
        let xcworkspacePath = path.appending(component: "Project.xcworkspace")
        let subject = XcodeBuildTarget.workspace(xcworkspacePath)

        // When
        let got = subject.xcodebuildArguments

        // Then
        XCTAssertEqual(got, ["-workspace", xcworkspacePath.pathString])
    }
}
