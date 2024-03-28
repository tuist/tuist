import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

final class EditAcceptanceTestiOSAppWithHelpers: TuistAcceptanceTestCase {
    func test_ios_app_with_helpers() async throws {
        let context = MockContext()
        try setUpFixture(.iosAppWithHelpers)
        try await run(EditCommand.self, context: context)
        try build(scheme: "Manifests")
    }
}

final class EditAcceptanceTestPlugin: TuistAcceptanceTestCase {
    func test_plugin() async throws {
        let context = MockContext()
        try setUpFixture(.plugin)
        try await run(EditCommand.self, context: context)
        try build(scheme: "Plugins")
    }
}

final class EditAcceptanceTestAppWithPlugins: TuistAcceptanceTestCase {
    func test_app_with_plugins() async throws {
        let context = MockContext()
        try setUpFixture(.appWithPlugins)
        try await run(InstallCommand.self, context: context)
        try await run(EditCommand.self, context: context)
        try build(scheme: "Manifests")
        try build(scheme: "Plugins")
        try build(scheme: "LocalPlugin")
    }
}

final class EditAcceptanceTestAppWithSPMDependencies: TuistAcceptanceTestCase {
    func test_app_with_spm_dependencies() async throws {
        let context = MockContext()
        try setUpFixture(.appWithSpmDependencies)
        try await run(EditCommand.self, context: context)
        try build(scheme: "Manifests")
    }
}

final class EditAcceptanceTestSPMPackage: TuistAcceptanceTestCase {
    func test_spm_package() async throws {
        let context = MockContext()
        try setUpFixture(.spmPackage)
        try await run(EditCommand.self, context: context)
        try build(scheme: "Manifests")
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
