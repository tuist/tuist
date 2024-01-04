import Foundation
import TSCBasic
import TuistSupport
import XCTest
@testable import TuistCore
@testable import TuistSupportTesting

final class XcodeBuildControllerCreateXCFrameworkArgumentTests: TuistUnitTestCase {
    func test_xcodebuildArguments() throws {
        // When: Framework
        let archive = try AbsolutePath(validating: "/test.xcarchive")
        let framework = "Test.framework"
        XCTAssertEqual(
            XcodeBuildControllerCreateXCFrameworkArgument.framework(archivePath: archive, framework: framework)
                .xcodebuildArguments,
            ["-archive", archive.pathString, "-framework", framework]
        )

        // When: Library
        let library = try AbsolutePath(validating: "/library.a")
        let headers = try AbsolutePath(validating: "/headers")
        XCTAssertEqual(XcodeBuildControllerCreateXCFrameworkArgument.library(
            path: library,
            headers: headers
        ).xcodebuildArguments, [
            "-library",
            library.pathString,
            "-headers",
            headers.pathString,
        ])
    }
}
