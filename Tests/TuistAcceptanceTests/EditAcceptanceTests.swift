import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

final class EditAcceptanceTestiOSAppWithHelpers: TuistAcceptanceTestCase {
    func test_ios_app_with_helpers() async throws {
        try setUpFixture("ios_app_with_helpers")
        try await run(EditCommand.self)
        try build(scheme: "Manifests")
    }
}

final class EditAcceptanceTestPlugin: TuistAcceptanceTestCase {
    func test_plugin() async throws {
        try setUpFixture("plugin")
        try await run(EditCommand.self)
        try build(scheme: "Plugins")
    }
}

final class EditAcceptanceTestAppWithPlugins: TuistAcceptanceTestCase {
    func test_app_with_plugins() async throws {
        try setUpFixture("app_with_plugins")
        try await run(FetchCommand.self)
        try await run(EditCommand.self)
        try build(scheme: "Manifests")
        try build(scheme: "Plugins")
        try build(scheme: "LocalPlugin")
    }
}

extension TuistAcceptanceTestCase {
    fileprivate func build(scheme: String) throws {
        try System.shared.runAndPrint(
            [
                "/usr/bin/xcrun",
                "xcodebuild",
                "clean",
                "build",
                "-scheme",
                scheme,
                "-workspace",
                workspacePath.pathString,
            ]
        )
    }
}
