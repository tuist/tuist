import Basic
import Foundation
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

final class TargetLinterTests: XCTestCase {
    var subject: TargetLinter!
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()
        fileHandler = try! MockFileHandler()
        subject = TargetLinter(fileHandler: fileHandler)
    }

    func test_lint_when_target_has_invalid_bundle_identifier() {
        let XCTAssertInvalidBundleId: (String) -> Void = { bundleId in
            let target = Target.test(bundleId: bundleId)
            let got = self.subject.lint(target: target)
            let reason = "Invalid bundle identifier '\(bundleId)'. This string must be a uniform type identifier (UTI) that contains only alphanumeric (A-Z,a-z,0-9), hyphen (-), and period (.) characters."
            XCTAssertTrue(got.contains(LintingIssue(reason: reason, severity: .error)))
        }
        let XCTAssertValidBundleId: (String) -> Void = { bundleId in
            let target = Target.test(bundleId: bundleId)
            let got = self.subject.lint(target: target)
            XCTAssertNil(got.first(where: { $0.description.contains("Invalid bundle identifier") }))
        }

        XCTAssertInvalidBundleId("_.company.app")
        XCTAssertInvalidBundleId("com.company.◌́")
        XCTAssertInvalidBundleId("Ⅻ.company.app")
        XCTAssertInvalidBundleId("ؼ.company.app")
        XCTAssertValidBundleId("com.company.MyModule${BUNDLE_SUFFIX}")
    }

    func test_lint_when_target_no_source_files() {
        let target = Target.test(sources: [])
        let got = subject.lint(target: target)
        XCTAssertTrue(got.contains(LintingIssue(reason: "The target \(target.name) doesn't contain source files.", severity: .warning)))
    }

    func test_lint_when_a_infoplist_file_is_being_copied() {
        let path = AbsolutePath("/Info.plist")
        let target = Target.test(resources: [path])

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "Info.plist at path \(path.asString) being copied into the target \(target.name) product.", severity: .warning)))
    }

    func test_lint_when_a_entitlements_file_is_being_copied() {
        let path = AbsolutePath("/App.entitlements")
        let target = Target.test(resources: [path])

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "Entitlements file at path \(path.asString) being copied into the target \(target.name) product.", severity: .warning)))
    }

    func test_lint_when_entitlements_not_missing() {
        let path = fileHandler.currentPath.appending(component: "Info.plist")
        let target = Target.test(infoPlist: path)

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "Info.plist file not found at path \(path.asString)", severity: .error)))
    }

    func test_lint_when_infoplist_not_found() {
        let path = fileHandler.currentPath.appending(component: "App.entitlements")
        let target = Target.test(entitlements: path)

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "Entitlements file not found at path \(path.asString)", severity: .error)))
    }

    func test_lint_when_library_has_resources() {
        let path = fileHandler.currentPath.appending(component: "Image.png")

        let staticLibrary = Target.test(product: .staticLibrary, resources: [path])
        let dynamicLibrary = Target.test(product: .dynamicLibrary, resources: [path])

        let staticResult = subject.lint(target: staticLibrary)
        XCTAssertTrue(staticResult.contains(LintingIssue(reason: "Target \(staticLibrary.name) cannot contain resources. Libraries don't support resources", severity: .error)), staticResult.description)

        let dynamicResult = subject.lint(target: staticLibrary)
        XCTAssertTrue(dynamicResult.contains(LintingIssue(reason: "Target \(dynamicLibrary.name) cannot contain resources. Libraries don't support resources", severity: .error)), dynamicResult.description)
    }

    func test_lint_when_main_storyboard_contains_file_extension() {
        let target = Target.test(mainStoryboard: "Main.storyboard")

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "mainStoryboard value should not inculed the .storyboard extension", severity: .error)))
    }

    func test_lint_when_launch_screen_storyboard_contains_file_extension() {
        let target = Target.test(launchScreenStoryboard: "Launch Screen.storyboard")

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "launchScreenStoryboard value should not inculed the .storyboard extension", severity: .error)))
    }

    func test_lint_when_launch_screen_storyboard_is_not_supported_by_platform() {
        let target = Target.test(platform: .macOS,
                                 launchScreenStoryboard: "Launch Screen.storyboard")

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "\(target.platform) does not support launch screens so the launchScreenStoryboard property will be ignored", severity: .warning)))
    }
}
