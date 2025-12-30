import Command
import FileSystem
import Testing
import TuistAcceptanceTesting
import TuistSupport
import TuistTesting
import XcodeProj
import XCTest

@testable import TuistKit

/// SwiftPM stores the registry configuration globally, and that prevents us from running these tests in parallel.
@Suite(.serialized)
struct DependenciesAcceptanceTests {
    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixture("generated_app_with_spm_dependencies"),
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

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_app_with_registry_and_alamofire")
    )
    func app_with_registry_and_alamofire() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // When: Set up registry
        try await TuistTest.run(
            RegistrySetupCommand.self,
            ["--path", fixtureDirectory.pathString]
        )

        // When: Install dependencies
        try await TuistTest.run(
            InstallCommand.self,
            ["--path", fixtureDirectory.pathString]
        )

        // When: Generate and build
        try await TuistTest.run(
            GenerateCommand.self,
            ["--path", fixtureDirectory.pathString, "--no-open"]
        )
        try await TuistTest.run(
            BuildCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString]
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_app_with_registry_and_alamofire_as_xcode_package")
    )
    func app_with_registry_and_alamofire_as_xcode_package() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // When: Set up registry
        try await TuistTest.run(
            RegistrySetupCommand.self,
            ["--path", fixtureDirectory.pathString]
        )

        // When: Generate and build
        try await TuistTest.run(
            GenerateCommand.self,
            ["--path", fixtureDirectory.pathString, "--no-open"]
        )
        try await TuistTest.run(
            BuildCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString]
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_package_with_registry_and_alamofire")
    )
    func package_with_registry_and_alamofire() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)

        // When: Set up registry
        try await TuistTest.run(
            RegistrySetupCommand.self,
            ["--path", fixtureDirectory.pathString]
        )

        // When: Build
        let commandRunner = CommandRunner()
        try await commandRunner.run(
            arguments: [
                "/usr/bin/swift",
                "package",
                "reset",
            ],
            workingDirectory: fixtureDirectory
        ).awaitCompletion()
        try await commandRunner.run(
            arguments: [
                "/usr/bin/swift",
                "build",
                "--only-use-versions-from-resolved-file",
            ],
            workingDirectory: fixtureDirectory
        ).awaitCompletion()
    }

    @Test(
        .disabled(), // I'll enable it in a separate PR.
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("xcode_project_with_registry_and_alamofire")
    )
    func xcode_project_with_registry_and_alamofire() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // When: Set up registry
        try await TuistTest.run(
            RegistrySetupCommand.self,
            ["--path", fixtureDirectory.pathString]
        )

        // When: Build
        let commandRunner = CommandRunner()
        try await commandRunner.run(
            arguments: [
                "/usr/bin/xcrun",
                "xcodebuild",
                "clean",
                "build",
                "-project",
                fixtureDirectory.appending(component: "App.xcodeproj").pathString,
                "-scheme",
                "App",
                "-sdk",
                "iphonesimulator",
                "-derivedDataPath",
                temporaryDirectory.pathString,
                "-onlyUsePackageVersionsFromResolvedFile",
            ]
        ).pipedStream().awaitCompletion()
    }
}

final class DependenciesAcceptanceTestAppWithSPMDependenciesWithoutInstall: TuistAcceptanceTestCase {
    func test() async throws {
        try await setUpFixture("generated_app_with_spm_dependencies")
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
        try await setUpFixture("generated_app_with_alamofire")
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")
    }
}

final class DependenciesAcceptanceTestAppPocketSVG: TuistAcceptanceTestCase {
    func test_app_with_pocket_svg() async throws {
        try await setUpFixture("generated_app_with_pocket_svg")
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")
    }
}

final class DependenciesAcceptanceTestAppSBTUITestTunnel: TuistAcceptanceTestCase {
    func test_app_with_sbtuitesttunnel() async throws {
        try await setUpFixture("generated_app_with_sbtuitesttunnel")
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")
    }
}

final class DependenciesAcceptanceTestIosAppWithSPMDependencies: TuistAcceptanceTestCase {
    func test_ios_app_spm_dependencies() async throws {
        try await setUpFixture("generated_ios_app_with_spm_dependencies")
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")
        try await run(BuildCommand.self, "App", "--platform", "ios")
        try await run(TestCommand.self, "App")
    }
}

final class DependenciesAcceptanceTestIosAppWithSPMDependenciesForceResolvedVersions: TuistAcceptanceTestCase {
    func test_ios_app_spm_dependencies_force_resolved_versions() async throws {
        try await setUpFixture("generated_ios_app_with_spm_dependencies_forced_resolved_versions")
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
            try await setUpFixture("generated_ios_app_with_spm_dependencies")
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
        try await setUpFixture("generated_app_with_composable_architecture")
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App")
    }
}

final class DependenciesAcceptanceTestAppWithRealm: TuistAcceptanceTestCase {
    func test_app_with_realm() async throws {
        try await setUpFixture("generated_app_with_realm")
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class DependenciesAcceptanceTestAppSPMXCFrameworkDependency: TuistAcceptanceTestCase {
    func test_app_spm_xcframework_dependency() async throws {
        try await setUpFixture("generated_app_with_spm_xcframework_dependency")
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}

final class DependenciesAcceptanceTestAppWithAirshipSDK: TuistAcceptanceTestCase {
    func test_app_with_airship_sdk() async throws {
        try await setUpFixture("generated_app_with_airship_sdk")
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self)
    }
}
