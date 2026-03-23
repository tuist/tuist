import Foundation
import TuistCore
import TuistSupport
import XcodeGraph
import Testing
@testable import TuistGenerator

struct ProjectLinterTests {
    let targetLinter: MockTargetLinter
    let schemeLinter: MockSchemeLinter
    let settingsLinter: MockSettingsLinter
    let packageLinter: MockPackageLinter
    let subject: ProjectLinter
    init() {
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

    @Test
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
        #expect(got.isEmpty)
    }
}
