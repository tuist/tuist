import Foundation
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest
@testable import TuistGenerator

final class ProjectLinterTests: XCTestCase {
    var targetLinter: MockTargetLinter!
    var schemeLinter: MockSchemeLinter!
    var testPlanLinter: MockTestPlanLinter!
    var settingsLinter: MockSettingsLinter!
    var packageLinter: MockPackageLinter!

    var subject: ProjectLinter!

    override func setUp() {
        super.setUp()
        targetLinter = MockTargetLinter()
        schemeLinter = MockSchemeLinter()
        testPlanLinter = MockTestPlanLinter()
        settingsLinter = MockSettingsLinter()
        packageLinter = MockPackageLinter()
        subject = ProjectLinter(
            targetLinter: targetLinter,
            settingsLinter: settingsLinter,
            schemeLinter: schemeLinter,
            testPlanLinter: testPlanLinter,
            packageLinter: packageLinter
        )
    }

    override func tearDown() {
        subject = nil
        settingsLinter = nil
        schemeLinter = nil
        testPlanLinter = nil
        targetLinter = nil
        packageLinter = nil
        super.tearDown()
    }

    func test_lint_valid_watchTargetBundleIdentifiers() async throws {
        // Given
        let app = Target.test(name: "App", product: .app, bundleId: "app")
        let watchApp = Target.test(name: "WatchApp", product: .watch2App, bundleId: "app.watchapp")
        let watchExtension = Target.test(
            name: "WatchExtension",
            product: .watch2Extension,
            bundleId: "app.watchapp.watchextension"
        )
        let project = Project.test(targets: [app, watchApp, watchExtension])

        // When
        let got = try await subject.lint(project)

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_lint_includes_test_plan_linter_issues() async throws {
        // Given
        let project = Project.test()
        let expectedIssue = LintingIssue(reason: "Test plan issue", severity: .error)
        testPlanLinter.issues = [expectedIssue]

        // When
        let got = try await subject.lint(project)

        // Then
        XCTAssertEqual(got, [expectedIssue])
        XCTAssertEqual(testPlanLinter.lintedProjects.count, 1)
    }
}
