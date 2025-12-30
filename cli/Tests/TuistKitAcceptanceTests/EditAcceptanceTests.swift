import TuistAcceptanceTesting
import TuistSupport
import TuistTesting
import XcodeProj
import XCTest

final class EditAcceptanceTestiOSAppWithHelpers: TuistAcceptanceTestCase {
    func test_ios_app_with_helpers() async throws {
        try await setUpFixture("generated_ios_app_with_helpers")
        try await run(EditCommand.self)
        try build(scheme: "Manifests")
    }
}

final class EditAcceptanceTestPlugin: TuistAcceptanceTestCase {
    func test_plugin() async throws {
        try await setUpFixture("generated_plugin")
        try await run(EditCommand.self)
        try build(scheme: "Plugins")
    }
}

final class EditAcceptanceTestAppWithPlugins: TuistAcceptanceTestCase {
    func test_app_with_plugins() async throws {
        try await setUpFixture("generated_app_with_plugins")
        try await run(InstallCommand.self)
        try await run(EditCommand.self)
        try build(scheme: "Manifests")
        try build(scheme: "Plugins")
        try build(scheme: "LocalPlugin")
    }
}

final class EditAcceptanceTestAppWithSPMDependencies: TuistAcceptanceTestCase {
    func test_app_with_spm_dependencies() async throws {
        try await setUpFixture("generated_app_with_spm_dependencies")
        try await run(EditCommand.self)
        try build(scheme: "Manifests")
    }
}

final class EditAcceptanceTestSPMPackage: TuistAcceptanceTestCase {
    func test_spm_package() async throws {
        try await setUpFixture("generated_spm_package")
        try await run(EditCommand.self)
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
