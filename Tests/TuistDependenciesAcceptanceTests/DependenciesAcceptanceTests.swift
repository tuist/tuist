import Command
import FileSystem
import Testing
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

@testable import TuistKit

struct DependenciesAcceptanceTests {
    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixture("app_with_spm_dependencies"),
        .withTestingSimulator("iPhone 16 Pro")
    )
    func app_with_spm_dependencies() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let simulator = try #require(Simulator.testing)

        // When: Build
        try await TuistTest.run(
            InstallCommand.self,
            ["--path", fixtureDirectory.pathString]
        )
        try await TuistTest.run(
            GenerateCommand.self,
            ["--path", fixtureDirectory.pathString, "--no-open"]
        )
        try await TuistTest.run(
            BuildCommand.self,
            ["App", "--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString]
        )
        try await TuistTest.run(
            BuildCommand.self,
            [
                "App",
                "--platform",
                "ios",
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                temporaryDirectory.pathString,
            ]
        )
        try await TuistTest.run(
            TestCommand.self,
            [
                "AppKit",
                "--device",
                simulator.name,
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                temporaryDirectory.pathString,
            ]
        )
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

final class DependenciesAcceptanceTestAppPocketSVG: TuistAcceptanceTestCase {
    func test_app_with_pocket_svg() async throws {
        try await setUpFixture(.appWithPocketSVG)
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")
    }
}

final class DependenciesAcceptanceTestAppRegistryAndAlamofire: ServerAcceptanceTestCase {
    func test_app_with_registry_and_alamofire() async throws {
        try await withMockedDependencies {
            try await setUpFixture(.appWithRegistryAndAlamofire)
            try await run(RegistrySetupCommand.self)
            try await run(RegistryLoginCommand.self)
            try await run(InstallCommand.self)
            try await run(GenerateCommand.self)
            try await run(BuildCommand.self, "App")
            try await run(RegistryLogoutCommand.self)
            try await run(CleanCommand.self, "dependencies")
            await XCTAssertThrows(try await run(InstallCommand.self))
        }
    }
}

final class DependenciesAcceptanceTestAppRegistryAndAlamofireAsXcodePackage: ServerAcceptanceTestCase {
    func test_app_with_registry_and_alamofire() async throws {
        try await withMockedDependencies {
            try await setUpFixture(.appWithRegistryAndAlamofireAsXcodePackage)
            try await run(RegistrySetupCommand.self)
            try await run(RegistryLoginCommand.self)
            try await run(GenerateCommand.self)
            try await run(BuildCommand.self, "App")
        }
    }
}

final class DependenciesAcceptanceTestAppSBTUITestTunnel: TuistAcceptanceTestCase {
    func test_app_with_sbtuitesttunnel() async throws {
        try await setUpFixture(.appWithSBTUITestTunnel)
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
        try await withMockedDependencies {
            try await setUpFixture(.iosAppWithSpmDependencies)
            try await run(InstallCommand.self)
            let packageResolvedPath = fixturePath.appending(components: ["Tuist", "Package.resolved"])
            let packageResolvedContents = try await fileSystem.readTextFile(at: packageResolvedPath)
            try FileHandler.shared.write(packageResolvedContents + " ", path: packageResolvedPath, atomically: true)
            try await run(GenerateCommand.self)
            XCTAssertEqual(
                ui()
                    .contains("We detected outdated dependencies"), true
            )
            resetUI()

            try await run(InstallCommand.self)
            try await run(GenerateCommand.self)
            XCTAssertEqual(
                ui()
                    .contains("We detected outdated dependencies"), false
            )
        }
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

final class DependenciesAcceptanceTestAppSPMXCFrameworkDependency: TuistAcceptanceTestCase {
    func test_app_spm_xcframework_dependency() async throws {
        try await setUpFixture(.appWithSpmXcframeworkDependency)
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

final class DependenciesAcceptanceTestPackageWithRegistryAndAlamofire: ServerAcceptanceTestCase {
    func test_app_with_registry_and_alamofire() async throws {
        try await withMockedDependencies {
            try await setUpFixture(.packageWithRegistryAndAlamofire)
            try await run(RegistrySetupCommand.self)
            try await run(RegistryLoginCommand.self)
            let commandRunner = CommandRunner()
            _ = try await commandRunner.run(
                arguments: [
                    "/usr/bin/swift",
                    "package",
                    "reset",
                ],
                workingDirectory: fixturePath
            ).concatenatedString()
            _ = try await commandRunner.run(
                arguments: [
                    "/usr/bin/swift",
                    "build",
                    "--only-use-versions-from-resolved-file",
                ],
                workingDirectory: fixturePath
            ).concatenatedString()
        }
    }
}

final class DependenciesAcceptanceTestXcodeProjectWithRegistryAndAlamofire: ServerAcceptanceTestCase {
    func test_xcode_project_with_registry_and_alamofire() async throws {
        try await withMockedDependencies {
            try await setUpFixture(.xcodeProjectWithRegistryAndAlamofire)
            try await run(RegistrySetupCommand.self)
            try await run(RegistryLoginCommand.self)
            let commandRunner = CommandRunner()
            _ = try await commandRunner.run(
                arguments: [
                    "/usr/bin/xcrun",
                    "xcodebuild",
                    "clean",
                    "build",
                    "-project",
                    fixturePath.appending(component: "App.xcodeproj").pathString,
                    "-scheme",
                    "App",
                    "-sdk",
                    "iphonesimulator",
                    "-derivedDataPath",
                    derivedDataPath.pathString,
                    "-onlyUsePackageVersionsFromResolvedFile",
                ]
            )
            .concatenatedString()
        }
    }
}
