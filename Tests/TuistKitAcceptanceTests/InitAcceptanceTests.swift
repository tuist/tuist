import Path
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

final class InitAcceptanceTestmacOSApp: TuistAcceptanceTestCase {
    func test_init_macos_app() async throws {
        try await run(InitCommand.self, "--platform", "macos", "--name", "Test")
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class InitAcceptanceTestiOSApp: TuistAcceptanceTestCase {
    func test_init_ios_app() async throws {
        try await run(InitCommand.self, "--platform", "ios", "--name", "My-App")
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

// TODO: Fix
// final class InitAcceptanceTesttvOSApp: TuistAcceptanceTestCase {
//    func test_init_tvos_app() async throws {
//        try run(InitCommand.self, "--platform", "tvos", "--name", "TvApp")
//        try await run(BuildCommand.self)
//    }
// }

final class InitAcceptanceTestCLIProjectWithTemplateInADifferentRepository: TuistAcceptanceTestCase {
    func test_cli_project_with_template_in_a_different_repository() async throws {
        try await run(
            InitCommand.self,
            "--template",
            "https://github.com/tuist/ExampleTuistTemplate-Tuist4.git",
            "--name",
            "MyApp"
        )
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}
