import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

final class PluginAcceptanceTestTuistPlugin: TuistAcceptanceTestCase {
    func test_tuist_plugin() async throws {
        let context = MockContext()
        try setUpFixture(.tuistPlugin)
        try await run(PluginBuildCommand.self, context: context)
        try await run(PluginRunCommand.self, "tuist-create-file", context: context)
    }
}

final class PluginAcceptanceTestAppWithPlugins: TuistAcceptanceTestCase {
    func test_app_with_plugins() async throws {
        let context = MockContext()
        try setUpFixture(.appWithPlugins)
        try await run(InstallCommand.self, context: context)
        try await run(GenerateCommand.self, context: context)
        try await run(BuildCommand.self, context: context)
    }
}
