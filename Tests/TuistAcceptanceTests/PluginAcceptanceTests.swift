import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

final class PluginAcceptanceTestTuistPlugin: TuistAcceptanceTestCase {
    func test_tuist_plugin() async throws {
        try setUpFixture(.tuistPlugin)
        try run(PluginBuildCommand.self)
        try run(PluginRunCommand.self, "tuist-create-file")
    }
}

final class PluginAcceptanceTestAppWithPlugins: TuistAcceptanceTestCase {
    func test_app_with_plugins() async throws {
        try setUpFixture(.appWithPlugins)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}
