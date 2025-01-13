import Foundation
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeGraph
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class ProjectLinterTests: TuistUnitTestCase {
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
        XCTAssertTrue(got.count == 2)
    }

    func test_lint_valid_externalProject() async throws {
        // Given
        let framework1 = Target.test(name: "Framework1", product: .framework)
        let framework2 = Target.test(name: "Framework2", product: .framework)
        let project = Project.test(targets: [framework1, framework2], type: .external(hash: nil))

        // When
        let got = try await subject.lint(project)

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_lint_valid_localProject() async throws {
        // Given
        let framework1 = Target.test(name: "Framework1", product: .framework)
        let framework2 = Target.test(name: "Framework2", product: .framework)
        let project = Project.test(targets: [framework1, framework2], type: .local)

        // When
        let got = try await subject.lint(project)

        // Then
        XCTAssertTrue(got.count == 2)
    }

    func test_lint_when_target_no_source_files() async throws {
        let target = Target.test(sources: [])
        let project = Project.test(targets: [target], type: .local)
        let got = try await subject.lint(project)

        XCTContainsLintingIssue(
            got,
            LintingIssue(reason: "The target \(target.name) doesn't contain source files.", severity: .warning)
        )
    }

    func test_lint_when_framework_has_resources_with_disable_bundle_accessors() async throws {
        let temporaryPath = try temporaryPath()
        let path = temporaryPath.appending(component: "Image.png")
        let element = ResourceFileElement.file(path: path)

        let staticFramework = Target.test(product: .staticFramework, resources: .init([element]))
        let dynamicFramework = Target.test(product: .framework, resources: .init([element]))

        let staticFrameworkResult = try await subject.lint(Project.test(targets: [staticFramework], type: .local))
        XCTContainsLintingIssue(
            staticFrameworkResult,
            LintingIssue(reason: "The target \(staticFramework.name) doesn't contain source files.", severity: .warning)
        )

        let dynamicFrameworkResult = try await subject.lint(Project.test(targets: [dynamicFramework], type: .local))
        XCTDoesNotContainLintingIssue(
            dynamicFrameworkResult,
            LintingIssue(
                reason: "Target \(dynamicFramework.name) cannot contain resources. For \(dynamicFramework.product) targets to support resources, 'Bundle Accessors' feature should be enabled.",
                severity: .error
            )
        )
    }

    func test_lint_when_ios_bundle_has_sources() async throws {
        // Given
        let bundle = Target.empty(
            destinations: .iOS,
            product: .bundle,
            sources: [
                SourceFile(path: "/path/to/some/source.swift"),
            ],
            resources: .init([])
        )

        // When
        let result = try await subject.lint(Project.test(targets: [bundle], type: .local))

        // Then
        XCTContainsLintingIssue(
            result,
            LintingIssue(
                reason: "Target \(bundle.name) cannot contain sources. bundle targets in one of these destinations doesn't support source files: iPad, iPhone, macWithiPadDesign",
                severity: .error
            )
        )
    }
}
