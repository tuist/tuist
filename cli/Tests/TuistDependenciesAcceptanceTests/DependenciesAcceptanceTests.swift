import Command
import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistAcceptanceTesting
import TuistBuildCommand
import TuistCacheCommand
import TuistGenerateCommand
import TuistLoggerTesting
import TuistLogging
import TuistNooraTesting
import TuistRegistryCommand
import TuistSupport
import TuistTestCommand
import TuistTesting

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

struct DependenciesAcceptanceTestAppWithSPMDependenciesWithoutInstall {
    @Test(.withFixture("generated_app_with_spm_dependencies"))
    func test() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        do {
            try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        } catch {
            #expect(
                (error as? FatalError)?.description
                    == "We could not find external dependencies. Run `tuist install` before you continue."
            )
            return
        }
        Issue.record("Generate should have failed.")
    }
}

struct DependenciesAcceptanceTestAppAlamofire {
    @Test(.withFixture("generated_app_with_alamofire"), .inTemporaryDirectory)
    func app_with_alamofire() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["App", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }
}

struct DependenciesAcceptanceTestAppWithObjCStaticFrameworkWithResources {
    @Test(.withFixture("generated_app_with_objc_static_framework_with_resources"), .inTemporaryDirectory)
    func app_with_objc_static_framework_with_resources() async throws {
        let fileSystem = FileSystem()
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["App", "--platform", "ios", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )

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

        try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "boot", simulatorId]
        ).pipedStream().awaitCompletion()

        let appPath = derivedDataPath
            .appending(components: ["Build", "Products", "Debug-iphonesimulator", "App.app"])

        try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "install", simulatorId, appPath.pathString]
        ).pipedStream().awaitCompletion()

        try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "launch", simulatorId, "dev.tuist.app"]
        ).pipedStream().awaitCompletion()

        try await Task.sleep(for: .seconds(2))

        let listOutput = try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "spawn", simulatorId, "launchctl", "list"]
        ).concatenatedString()

        #expect(
            listOutput.contains("UIKitApplication:dev.tuist.app"),
            "App should still be running after launch. If it crashed, the bundle accessor for ObjC static frameworks with resources may be broken."
        )

        try await Task.sleep(for: .seconds(1))

        let finalListOutput = try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "spawn", simulatorId, "launchctl", "list"]
        ).concatenatedString()

        #expect(
            finalListOutput.contains("UIKitApplication:dev.tuist.app"),
            "App should remain running. If it crashed after initial launch, there may be a delayed resource loading issue."
        )
    }

    @Test(.withFixture("generated_app_with_objc_static_framework_with_resources"), .inTemporaryDirectory)
    func app_with_objc_static_framework_with_resources_from_cache() async throws {
        let fileSystem = FileSystem()
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(CacheCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["App", "--platform", "ios", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )

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

        try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "boot", simulatorId]
        ).pipedStream().awaitCompletion()

        let appPath = derivedDataPath
            .appending(components: ["Build", "Products", "Debug-iphonesimulator", "App.app"])

        let frameworksPath = appPath.appending(component: "Frameworks")
        let frameworksExist = await (try? fileSystem.exists(frameworksPath)) ?? false
        #expect(
            frameworksExist,
            "Frameworks directory should exist when using cached XCFrameworks"
        )

        if frameworksExist {
            let frameworkContents = try await fileSystem.glob(directory: frameworksPath, include: ["*.framework"]).collect()
            #expect(
                frameworkContents.contains { $0.basename.contains("SVProgressHUD") },
                "SVProgressHUD.framework should be embedded in the app bundle when using cached static XCFramework with resources"
            )
        }

        let resourceBundlePath = appPath.appending(component: "SVProgressHUD_SVProgressHUD.bundle")
        let resourceBundleExists = await (try? fileSystem.exists(resourceBundlePath)) ?? false
        #expect(
            !resourceBundleExists,
            "SVProgressHUD_SVProgressHUD.bundle should not exist; resources live inside the framework itself"
        )

        try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "install", simulatorId, appPath.pathString]
        ).pipedStream().awaitCompletion()

        try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "launch", simulatorId, "dev.tuist.app"]
        ).pipedStream().awaitCompletion()

        try await Task.sleep(for: .seconds(2))

        let listOutput = try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "spawn", simulatorId, "launchctl", "list"]
        ).concatenatedString()

        #expect(
            listOutput.contains("UIKitApplication:dev.tuist.app"),
            "App should still be running after launch when using cached XCFrameworks. If it crashed, the static XCFramework with resources may not be embedded correctly."
        )

        try await Task.sleep(for: .seconds(1))

        let finalListOutput = try await commandRunner.run(
            arguments: ["/usr/bin/xcrun", "simctl", "spawn", simulatorId, "launchctl", "list"]
        ).concatenatedString()

        #expect(
            finalListOutput.contains("UIKitApplication:dev.tuist.app"),
            "App should remain running when using cached XCFrameworks. If it crashed, the bundle accessor for cached static frameworks with resources may be broken."
        )
    }
}

struct DependenciesAcceptanceTestAppPocketSVG {
    @Test(.withFixture("generated_app_with_pocket_svg"), .inTemporaryDirectory)
    func app_with_pocket_svg() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["App", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }
}

struct DependenciesAcceptanceTestAppSBTUITestTunnel {
    @Test(.withFixture("generated_app_with_sbtuitesttunnel"), .inTemporaryDirectory)
    func app_with_sbtuitesttunnel() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["App", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }
}

struct DependenciesAcceptanceTestIosAppWithSPMDependencies {
    @Test(.withFixture("generated_ios_app_with_spm_dependencies"), .inTemporaryDirectory)
    func ios_app_spm_dependencies() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["App", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
        try await TuistTest.run(
            BuildCommand.self,
            ["App", "--platform", "ios", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
        try await TuistTest.run(
            TestCommand.self,
            ["App", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }
}

struct DependenciesAcceptanceTestIosAppWithSPMDependenciesForceResolvedVersions {
    @Test(.withFixture("generated_ios_app_with_spm_dependencies_forced_resolved_versions"), .inTemporaryDirectory)
    func ios_app_spm_dependencies_force_resolved_versions() async throws {
        let fileSystem = FileSystem()
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        let packageResolvedPath = fixtureDirectory.appending(components: ["Tuist", "Package.resolved"])
        let packageResolvedContents = try await fileSystem.readTextFile(at: packageResolvedPath)
        #expect(packageResolvedContents.contains(#""version" : "5.0.0""#))
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["App", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
        try await TuistTest.run(
            TestCommand.self,
            ["App", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }
}

struct DependenciesAcceptanceTestIosAppWithSPMDependenciesWithOutdatedDependencies {
    @Test(.withFixture("generated_ios_app_with_spm_dependencies"), .withMockedDependencies())
    func test() async throws {
        let fileSystem = FileSystem()
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        let packageResolvedPath = fixtureDirectory.appending(components: ["Tuist", "Package.resolved"])
        let packageResolvedContents = try await fileSystem.readTextFile(at: packageResolvedPath)
        try FileHandler.shared.write(packageResolvedContents + " ", path: packageResolvedPath, atomically: true)
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        #expect(ui().contains("We detected outdated dependencies"))
        resetUI()

        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        #expect(ui().contains("We detected outdated dependencies") == false)
    }
}

struct DependenciesAcceptanceTestAppWithComposableArchitecture {
    @Test(.withFixture("generated_app_with_composable_architecture"), .inTemporaryDirectory)
    func app_with_composable_architecture() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["App", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }
}

struct DependenciesAcceptanceTestAppWithRealm {
    @Test(.withFixture("generated_app_with_realm"), .inTemporaryDirectory)
    func app_with_realm() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }
}

struct DependenciesAcceptanceTestAppSPMXCFrameworkDependency {
    @Test(.withFixture("generated_app_with_spm_xcframework_dependency"), .inTemporaryDirectory)
    func app_spm_xcframework_dependency() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }
}

struct DependenciesAcceptanceTestAppWithAirshipSDK {
    @Test(.withFixture("generated_app_with_airship_sdk"), .inTemporaryDirectory)
    func app_with_airship_sdk() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }
}
