import Path
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

final class DependenciesAcceptanceTestAppWithSPMDependencies: TuistAcceptanceTestCase {
    func test_app_spm_dependencies() async throws {
        try await setUpFixture(.appWithSpmDependencies)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")
        try await run(BuildCommand.self, "App", "--platform", "ios")
        try await run(BuildCommand.self, "VisionOSApp")
        try await run(TestCommand.self, "AppKit")
    }
}

final class DependenciesAcceptanceTestAppWithSPMDependenciesWithoutInstall: TuistAcceptanceTestCase {
    func test() async throws {
        try await setUpFixture(.appWithSpmDependencies)
        do {
            try await run(GenerateCommand.self)
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

final class DependenciesAcceptanceTestAppAlamofire: TuistAcceptanceTestCase {
    func test_app_with_alamofire() async throws {
        try await setUpFixture(.appWithAlamofire)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")
    }
}

final class DependenciesAcceptanceTestIosAppWithSPMDependencies: TuistAcceptanceTestCase {
    func test_ios_app_spm_dependencies() async throws {
        try await setUpFixture(.iosAppWithSpmDependencies)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")
        try await run(BuildCommand.self, "App", "--platform", "ios")
        try await run(TestCommand.self, "App")
    }
}

final class DependenciesAcceptanceTestIosAppWithSPMDependenciesForceResolvedVersions: TuistAcceptanceTestCase {
    func test_ios_app_spm_dependencies_force_resolved_versions() async throws {
        try await setUpFixture(.iosAppWithSpmDependenciesForceResolvedVersions)
        try await run(InstallCommand.self)
        let packageResolvedPath = fixturePath.appending(components: ["Tuist", "Package.resolved"])
        let packageResolvedContents = try await fileSystem.readTextFile(at: packageResolvedPath)
        // NB: Should not modify SnapKit version in Package.resolved
        XCTAssertTrue(packageResolvedContents.contains(#""version" : "5.0.0""#))
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")
        try await run(TestCommand.self, "App")
    }
}

final class DependenciesAcceptanceTestIosAppWithSPMDependenciesWithOutdatedDependencies: TuistAcceptanceTestCase {
    func test() async throws {
        try await setUpFixture(.iosAppWithSpmDependencies)
        try await run(InstallCommand.self)
        let packageResolvedPath = fixturePath.appending(components: ["Tuist", "Package.resolved"])
        let packageResolvedContents = try await fileSystem.readTextFile(at: packageResolvedPath)
        try FileHandler.shared.write(packageResolvedContents + " ", path: packageResolvedPath, atomically: true)
        try await run(GenerateCommand.self)
        XCTAssertStandardOutput(pattern: "We detected outdated dependencies. Please run \"tuist install\" to update them.")
        TestingLogHandler.reset()
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        XCTAssertStandardOutputNotContains("We detected outdated dependencies. Please run \"tuist install\" to update them.")
    }
}

final class DependenciesAcceptanceTestAppWithComposableArchitecture: TuistAcceptanceTestCase {
    func test_app_with_composable_architecture() async throws {
        try await setUpFixture(.appWithComposableArchitecture)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")
    }
}

final class DependenciesAcceptanceTestAppWithRealm: TuistAcceptanceTestCase {
    func test_app_with_realm() async throws {
        try await setUpFixture(.appWithRealm)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class DependenciesAcceptanceTestAppWithAirshipSDK: TuistAcceptanceTestCase {
    func test_app_with_airship_sdk() async throws {
        try await setUpFixture(.appWithAirshipSDK)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}
