import Path
import XCTest
@testable import TuistSupport

final class SwiftPackageManagerScratchDirectoryLocatorTests: XCTestCase {
    private let subject = SwiftPackageManagerScratchDirectoryLocator()

    func test_locate_when_no_override_is_present() throws {
        let packagePath = try AbsolutePath(validating: "/tmp/project/Tuist")
        let workingDirectory = try AbsolutePath(validating: "/tmp/project")

        XCTAssertEqual(
            try subject.locate(
                packagePath: packagePath,
                arguments: [],
                environment: [:],
                workingDirectory: workingDirectory
            ),
            packagePath.appending(component: ".build")
        )
    }

    func test_locate_when_scratchPath_is_present() throws {
        let packagePath = try AbsolutePath(validating: "/tmp/project/Tuist")
        let workingDirectory = try AbsolutePath(validating: "/tmp/project")

        XCTAssertEqual(
            try subject.locate(
                packagePath: packagePath,
                arguments: ["--scratch-path", "custom-build"],
                environment: [:],
                workingDirectory: workingDirectory
            ),
            workingDirectory.appending(component: "custom-build")
        )
    }

    func test_locate_when_scratchPath_uses_equals_syntax() throws {
        let packagePath = try AbsolutePath(validating: "/tmp/project/Tuist")
        let workingDirectory = try AbsolutePath(validating: "/tmp/project")

        XCTAssertEqual(
            try subject.locate(
                packagePath: packagePath,
                arguments: ["--scratch-path=custom-build"],
                environment: [:],
                workingDirectory: workingDirectory
            ),
            workingDirectory.appending(component: "custom-build")
        )
    }

    func test_locate_when_buildPath_is_present() throws {
        let packagePath = try AbsolutePath(validating: "/tmp/project/Tuist")
        let workingDirectory = try AbsolutePath(validating: "/tmp/project")

        XCTAssertEqual(
            try subject.locate(
                packagePath: packagePath,
                arguments: ["--build-path", "custom-build"],
                environment: [:],
                workingDirectory: workingDirectory
            ),
            workingDirectory.appending(component: "custom-build")
        )
    }

    func test_locate_when_scratchPath_and_buildPath_are_present() throws {
        let packagePath = try AbsolutePath(validating: "/tmp/project/Tuist")
        let workingDirectory = try AbsolutePath(validating: "/tmp/project")

        XCTAssertEqual(
            try subject.locate(
                packagePath: packagePath,
                arguments: ["--build-path", "build-dir", "--scratch-path", "scratch-dir"],
                environment: [:],
                workingDirectory: workingDirectory
            ),
            workingDirectory.appending(component: "scratch-dir")
        )
    }

    func test_locate_when_swiftpmBuildDirectory_is_present() throws {
        let packagePath = try AbsolutePath(validating: "/tmp/project/Tuist")
        let workingDirectory = try AbsolutePath(validating: "/tmp/project")

        XCTAssertEqual(
            try subject.locate(
                packagePath: packagePath,
                arguments: ["--scratch-path", "scratch-dir"],
                environment: ["SWIFTPM_BUILD_DIR": "env-build-dir"],
                workingDirectory: workingDirectory
            ),
            workingDirectory.appending(component: "env-build-dir")
        )
    }
}
