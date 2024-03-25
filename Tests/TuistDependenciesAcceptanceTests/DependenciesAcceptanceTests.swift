import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

final class DependenciesAcceptanceTestAppWithSPMDependencies: TuistAcceptanceTestCase {
    func test_app_spm_dependencies() async throws {
        let context = MockContext()

        try setUpFixture(.appWithSpmDependencies)
        try await run(InstallCommand.self, context: context)
        try await run(GenerateCommand.self, context: context)
        try await run(BuildCommand.self, "App", context: context)
        try await run(BuildCommand.self, "VisionOSApp", context: context)
        try await run(TestCommand.self, "AppKit", context: context)
    }
}

final class DependenciesAcceptanceTestAppWithSPMDependenciesWithoutInstall: TuistAcceptanceTestCase {
    func test() async throws {
        let context = MockContext()
        try setUpFixture(.appWithSpmDependencies)
        do {
            try await run(GenerateCommand.self, context: context)
        } catch {
            XCTAssertEqual(
                (error as? FatalError)?.description,
                "We could not find external dependencies. Run `tuist install` before you continue."
            )
            return
        }
        XCTFail("Generate should have failed.")
    }
}
