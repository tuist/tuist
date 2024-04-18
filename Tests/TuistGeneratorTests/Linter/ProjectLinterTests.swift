import Foundation
import Path
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeGraph
import XCTest
@testable import TuistGenerator

final class ProjectLinterTests: XCTestCase {
    var targetLinter: MockTargetLinter!
    var schemeLinter: MockSchemeLinter!
    var settingsLinter: MockSettingsLinter!
    var packageLinter: MockPackageLinter!

    var subject: ProjectLinter!

    override func setUp() {
        super.setUp()
        targetLinter = MockTargetLinter()
        schemeLinter = MockSchemeLinter()
        settingsLinter = MockSettingsLinter()
        packageLinter = MockPackageLinter()
        subject = ProjectLinter(
            targetLinter: targetLinter,
            settingsLinter: settingsLinter,
            schemeLinter: schemeLinter,
            packageLinter: packageLinter
        )
    }

    override func tearDown() {
        subject = nil
        settingsLinter = nil
        schemeLinter = nil
        targetLinter = nil
        packageLinter = nil
        super.tearDown()
    }

    func test_validate_when_there_are_duplicated_targets() throws {
        let target = Target.test(name: "A")
        let project = Project.test(targets: [target, target])
        let got = subject.lint(project)
        XCTAssertTrue(
            got
                .contains(LintingIssue(
                    reason: "Targets A from project at \(project.path.pathString) have duplicates.",
                    severity: .error
                ))
        )
    }

    func test_validate_when_there_are_duplicated_target_product_names() throws {
        let target1 = Target.test(name: "A", productName: "B")
        let target2 = Target.test(name: "A1", productName: "B")
        var project = Project.test(targets: [target1, target2])
        var got = subject.lint(project)
        XCTAssertTrue(
            got
                .contains(LintingIssue(
                    reason: "Targets with product names and destinations B -- iPad,iPhone from project at \(project.path.pathString) have duplicates.",
                    severity: .error
                ))
        )

        // Confirm that we don't crash when the productName is nil
        let target3 = Target.test(name: "A", productName: "B")
        let target4 = Target.test(name: "A1")
        project = Project.test(targets: [target3, target4])
        got = subject.lint(project)

        XCTAssertTrue(got.isEmpty)
    }

    func test_lint_valid_watchTargetBundleIdentifiers() throws {
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
        let got = subject.lint(project)

        // Then
        XCTAssertTrue(got.isEmpty)
    }
}
