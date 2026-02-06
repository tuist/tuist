import Command
import FileSystem
import Testing
import TuistAcceptanceTesting
import TuistCacheCommand
import TuistLogging
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

final class DependenciesAcceptanceTestAppWithObjCStaticFrameworkWithResources: TuistAcceptanceTestCase {
    func test_app_with_objc_static_framework_with_resources() async throws {
        try await setUpFixture("generated_app_with_objc_static_framework_with_resources")
        try await run(InstallCommand.self)
        try await run(GenerateCommand.self)
        try await run(BuildCommand.self, "App", "--platform", "ios")

        // Create a simulator for testing
        let commandRunner = CommandRunner()
        let simulatorId = UUID().uuidString
        try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "create", simulatorId, "iPhone 16 Pro"]
        ).pipedStream().awaitCompletion()

        defer {
            Task {
                try? await commandRunner.run(
                    arguments: ["/usr/bin/xcrun", "simctl", "delete", simulatorId]
                ).pipedStream().awaitCompletion()
            }
        }

        // Boot the simulator
        try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "boot", simulatorId]
        ).pipedStream().awaitCompletion()

        // Find the built app
        let appPath = derivedDataPath
            .appending(components: ["Build", "Products", "Debug-iphonesimulator", "App.app"])

        // Install the app
        try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "install", simulatorId, appPath.pathString]
        ).pipedStream().awaitCompletion()

        // Launch the app
        try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "launch", simulatorId, "dev.tuist.app"]
        ).pipedStream().awaitCompletion()

        // Wait a bit for the app to initialize and potentially crash
        try await Task.sleep(for: .seconds(2))

        // Verify the app is still running by checking if the process exists
        let listOutput = try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "spawn", simulatorId, "launchctl", "list"]
        ).concatenatedString()

        XCTAssertTrue(
            listOutput.contains("UIKitApplication:dev.tuist.app"),
            "App should still be running after launch. If it crashed, the bundle accessor for ObjC static frameworks with resources may be broken."
        )

        // Wait a bit more to ensure stability
        try await Task.sleep(for: .seconds(1))

        // Check again that the app is still running
        let finalListOutput = try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "spawn", simulatorId, "launchctl", "list"]
        ).concatenatedString()

        XCTAssertTrue(
            finalListOutput.contains("UIKitApplication:dev.tuist.app"),
            "App should remain running. If it crashed after initial launch, there may be a delayed resource loading issue."
        )
    }

    func test_app_with_objc_static_framework_with_resources_from_cache() async throws {
        try await setUpFixture("generated_app_with_objc_static_framework_with_resources")
        try await run(InstallCommand.self)

        // First, cache the targets to create XCFrameworks
        try await run(CacheCommand.self)

        // Generate with cached binaries
        try await run(GenerateCommand.self)

        // Build
        try await run(BuildCommand.self, "App", "--platform", "ios")

        // Create a simulator for testing
        let commandRunner = CommandRunner()
        let simulatorId = UUID().uuidString
        try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "create", simulatorId, "iPhone 16 Pro"]
        ).pipedStream().awaitCompletion()

        defer {
            Task {
                try? await commandRunner.run(
                    arguments: ["/usr/bin/xcrun", "simctl", "delete", simulatorId]
                ).pipedStream().awaitCompletion()
            }
        }

        // Boot the simulator
        try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "boot", simulatorId]
        ).pipedStream().awaitCompletion()

        // Find the built app
        let appPath = derivedDataPath
            .appending(components: ["Build", "Products", "Debug-iphonesimulator", "App.app"])

        // Verify that SVProgressHUD.xcframework is embedded (not the source target)
        let frameworksPath = appPath.appending(component: "Frameworks")
        let frameworksExist = await (try? fileSystem.exists(frameworksPath)) ?? false
        XCTAssertTrue(
            frameworksExist,
            "Frameworks directory should exist when using cached XCFrameworks"
        )

        if frameworksExist {
            let frameworkContents = try await fileSystem.glob(directory: frameworksPath, include: ["*.framework"]).collect()
            XCTAssertTrue(
                frameworkContents.contains { $0.basename.contains("SVProgressHUD") },
                "SVProgressHUD.framework should be embedded in the app bundle when using cached static XCFramework with resources"
            )
        }

        // Verify the separate resource bundle exists (external static frameworks generate SPM-style bundles)
        let resourceBundlePath = appPath.appending(component: "SVProgressHUD_SVProgressHUD.bundle")
        let resourceBundleExists = await (try? fileSystem.exists(resourceBundlePath)) ?? false
        XCTAssertTrue(
            resourceBundleExists,
            "SVProgressHUD_SVProgressHUD.bundle should exist in the app bundle for external static frameworks with resources"
        )

        // Install the app
        try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "install", simulatorId, appPath.pathString]
        ).pipedStream().awaitCompletion()

        // Launch the app
        try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "launch", simulatorId, "dev.tuist.app"]
        ).pipedStream().awaitCompletion()

        // Wait a bit for the app to initialize and potentially crash
        try await Task.sleep(for: .seconds(2))

        // Verify the app is still running by checking if the process exists
        let listOutput = try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "spawn", simulatorId, "launchctl", "list"]
        ).concatenatedString()

        XCTAssertTrue(
            listOutput.contains("UIKitApplication:dev.tuist.app"),
            "App should still be running after launch when using cached XCFrameworks. If it crashed, the static XCFramework with resources may not be embedded correctly."
        )

        // Wait a bit more to ensure stability
        try await Task.sleep(for: .seconds(1))

        // Check again that the app is still running
        let finalListOutput = try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "spawn", simulatorId, "launchctl", "list"]
        ).concatenatedString()

        XCTAssertTrue(
            finalListOutput.contains("UIKitApplication:dev.tuist.app"),
            "App should remain running when using cached XCFrameworks. If it crashed, the bundle accessor for cached static frameworks with resources may be broken."
        )
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
