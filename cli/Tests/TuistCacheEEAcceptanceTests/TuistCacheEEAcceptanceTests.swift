import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistAcceptanceTesting
import TuistServer
import TuistSupport
import TuistTesting
import XcodeProj

@testable import TuistCacheEE
@testable import TuistKit

struct TuistCacheEEAcceptanceTests {
    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixture("generated_framework_with_native_swift_macro")
    ) func framework_with_native_swift_macro() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let mockedEnvironment = try #require(Environment.mocked)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])

        // When: Cache the binaries
        try await TuistTest.run(
            CacheCommand.self,
            ["--path", fixtureDirectory.pathString]
        )

        // When: Generate with a focuson the App
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString, "Framework"])

        let xcodeProj =
            try XcodeProj(path: .init(fixtureDirectory.appending(component: "FrameworkWithSwiftMacro.xcodeproj").pathString))

        // We check that OTHER_SWIFT_FLAGS references the build directory as a proof
        // of the target linking pre-compiled Swift macros.
        let frameworkTarget = try #require(xcodeProj.pbxproj.targets(named: "Framework").first)
        let configurationList = try #require(frameworkTarget.buildConfigurationList)
        #expect(configurationList.buildConfigurations.isEmpty == false)
        for buildConfiguration in configurationList.buildConfigurations {
            let otherSwiftFlags = try #require(buildConfiguration.buildSettings["OTHER_SWIFT_FLAGS"]?.arrayValue)
            #expect(otherSwiftFlags.contains(where: { $0.contains(mockedEnvironment.cacheDirectory.pathString) }) == true)
        }
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixture("generated_ios_app_with_external_dependencies_filtered_out")
    ) func generated_ios_app_with_external_dependencies_filtered_out() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])

        // When: Cache the binaries
        try await TuistTest.run(
            CacheCommand.self,
            ["--path", fixtureDirectory.pathString]
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixture("generated_ios_app_with_frameworks_keeping_target_sources")
    ) func generated_ios_app_with_frameworks_keeping_target_sources() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let xcodeprojPath = fixtureDirectory.appending(component: "MainApp.xcodeproj")
        let xcworkspacePath = fixtureDirectory.appending(component: "MainApp.xcworkspace")
        let fileSystem = FileSystem()
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])

        // When: Cache the binaries
        try await TuistTest.run(
            CacheCommand.self,
            ["--path", fixtureDirectory.pathString]
        )

        // When: Generate with a focuson the App
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString, "Framework1"])

        // Then
        // The app doesn't get tree-shaked
        try TuistTest.expectContainsTarget("App", inXcodeProj: xcodeprojPath)

        try TuistTest.expectLinked("Framework1.framework", by: "App", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework2-iOS.xcframework", by: "App", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework3.xcframework", by: "App", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework4.xcframework", by: "App", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework5.xcframework", by: "App", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework3.xcframework", by: "Framework2-iOS", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework4.xcframework", by: "Framework2-iOS", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework5.xcframework", by: "Framework2-iOS", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework4.xcframework", by: "Framework3", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework5.xcframework", by: "Framework3", inXcodeProj: xcodeprojPath)
        try TuistTest.expectLinked("Framework5.xcframework", by: "Framework4", inXcodeProj: xcodeprojPath)

        // Then: Schemes
        let schemes = try await fileSystem.glob(directory: xcworkspacePath, include: ["xcshareddata/xcschemes/*.xcscheme"])
            .collect()
        let cachedSchemePath = try #require(schemes.first(where: { $0.basename == "MainApp-Cached.xcscheme" }))
        let cachedScheme = try XCScheme(pathString: cachedSchemePath.pathString)
        let schemeTargets = cachedScheme.buildAction?.buildActionEntries.map(\.buildableReference.blueprintName).sorted()
        #expect(schemeTargets == [
            "Framework2-iOS",
            "Framework2-macOS",
            "Framework3",
            "Framework4",
            "Framework5",
            "GoogleUtilities-NSData",
        ])

        // Then: Builds
        let arguments = [
            "-scheme", "App",
            "-destination", "generic/platform=iOS Simulator",
            "-workspace", xcworkspacePath.pathString,
            "-derivedDataPath", temporaryDirectory.pathString,
            "CODE_SIGN_IDENTITY=",
            "CODE_SIGNING_REQUIRED=NO",
            "CODE_SIGNING_ALLOWED=NO",
        ]
        try await TuistTest.run(XcodeBuildBuildCommand.self, arguments)
    }

    /// This test hangs when we run it as part of the deployment pipeline so we moved it here to run it only as part of
    /// PR changes.
    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("xcode_project_with_packages_and_tests"),
        .withTestingSimulator("iPhone 17")
    ) func xcode_project_with_packages_and_tests() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let xcodeprojPath = fixtureDirectory.appending(component: "App.xcodeproj")
        let simulator = try #require(Simulator.testing)
        let fileSystem = FileSystem()
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let arguments = [
            "-scheme", "App",
            "-destination", simulator.description,
            "-project", xcodeprojPath.pathString,
            "-derivedDataPath", temporaryDirectory.pathString,
            "CODE_SIGN_IDENTITY=",
            "CODE_SIGNING_REQUIRED=NO",
            "CODE_SIGNING_ALLOWED=NO",
        ]
        try await TuistTest.run(XcodeBuildTestCommand.self, arguments)
        resetUI()

        // When: I modify a file
        let filePath = fixtureDirectory.appending(
            components: [
                "App",
                "LibraryA",
                "Sources",
                "LibraryA",
                "LibraryA.swift",
            ]
        )
        var contents = try await fileSystem.readTextFile(at: filePath)
        contents += "// \(UUID().uuidString)"
        try await fileSystem.writeText(contents, at: filePath, options: Set([.overwrite]))

        // When: Running tests selectively
        try await TuistTest.run(XcodeBuildTestCommand.self, arguments)
        TuistTest
            .expectLogs(
                "The following targets have not changed since the last successful run and will be skipped: AppTests, LibraryBTests"
            )

        // Selective test results are persisted asynchronously and can take up to 5
        // seconds to be inserted.
        try await Task.sleep(nanoseconds: 7_000_000_000)
        try await TuistTest.run(
            CleanCommand.self, ["selectiveTests", "--path", fixtureDirectory.pathString]
        )
        try await Task.sleep(nanoseconds: 7_000_000_000)
        resetUI()

        // When: Running tests selectively
        try await TuistTest.run(XcodeBuildTestCommand.self, arguments)
        TuistTest.expectLogs("There are no tests to run, exiting early..")
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("xcode_project_with_ios_app_and_cas"),
        .withTestingSimulator("iPhone 17")
    ) func xcode_project_with_ios_app_and_cas() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let xcodeprojPath = fixtureDirectory.appending(component: "App.xcodeproj")
        let simulator = try #require(Simulator.testing)
        let fileSystem = FileSystem()
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        environment.stateDirectory = try await fileSystem.currentWorkingDirectory()
        let fixtureFullHandle = try #require(TuistTest.fixtureFullHandle)

        let backgroundTask = Task {
            while !Task.isCancelled {
                try await TuistTest.run(
                    CacheStartCommand.self,
                    [fixtureFullHandle, "--url", Environment.current.variables["TUIST_URL"] ?? "https://canary.tuist.dev"]
                )
            }
        }

        defer {
            backgroundTask.cancel()
        }

        let remoteCacheServicePath = environment.stateDirectory
            .appending(component: "\(fixtureFullHandle.replacingOccurrences(of: "/", with: "_")).sock")

        let arguments = [
            "-scheme", "App",
            "-destination", simulator.description,
            "-project", xcodeprojPath.pathString,
            "-derivedDataPath", temporaryDirectory.pathString,
            "CODE_SIGN_IDENTITY=",
            "CODE_SIGNING_REQUIRED=NO",
            "CODE_SIGNING_ALLOWED=NO",
            "COMPILATION_CACHE_REMOTE_SERVICE_PATH=\(remoteCacheServicePath.pathString)",
        ]
        try await TuistTest.run(XcodeBuildBuildCommand.self, arguments)
        TuistTest.expectLogs("note: 0 hits / 60 cacheable tasks (0%)")
        resetUI()

        try await fileSystem.remove(temporaryDirectory)

        try await TuistTest.run(XcodeBuildBuildCommand.self, arguments)
        TuistTest.expectLogs("note: 60 hits / 60 cacheable tasks (100%)")
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_project_with_caching_enabled"),
        .withTestingSimulator("iPhone 17")
    ) func generated_project_with_caching_enabled() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let xcodeprojPath = fixtureDirectory.appending(component: "App.xcodeproj")
        let simulator = try #require(Simulator.testing)
        let fileSystem = FileSystem()
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        environment.stateDirectory = try await fileSystem.currentWorkingDirectory()
        let fixtureFullHandle = try #require(TuistTest.fixtureFullHandle)

        try await fileSystem.writeText(
            """
            import ProjectDescription

            let tuist = Tuist(
                fullHandle: "\(fixtureFullHandle)",
                url: "\(Environment.current.variables["TUIST_URL"] ?? "https://canary.tuist.dev")",
                project: .tuist(
                    generationOptions: .options(
                        enableCaching: true
                    )
                )
            )
            """,
            at: fixtureDirectory.appending(components: "Tuist.swift"),
            options: Set([.overwrite])
        )

        let backgroundTask = Task {
            while !Task.isCancelled {
                try await TuistTest.run(
                    CacheStartCommand.self,
                    [fixtureFullHandle, "--url", Environment.current.variables["TUIST_URL"] ?? "https://canary.tuist.dev"]
                )
            }
        }

        defer {
            backgroundTask.cancel()
        }

        let remoteCacheServicePath = environment.stateDirectory
            .appending(component: "\(fixtureFullHandle.replacingOccurrences(of: "/", with: "_")).sock")

        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])
        resetUI()

        let arguments = [
            "-scheme", "App",
            "-destination", simulator.description,
            "-project", xcodeprojPath.pathString,
            "-derivedDataPath", temporaryDirectory.pathString,
            "CODE_SIGN_IDENTITY=",
            "CODE_SIGNING_REQUIRED=NO",
            "CODE_SIGNING_ALLOWED=NO",
            "COMPILATION_CACHE_REMOTE_SERVICE_PATH=\(remoteCacheServicePath.pathString)",
        ]
        try await TuistTest.run(XcodeBuildBuildCommand.self, arguments)
        TuistTest.expectLogs("cacheable tasks (0%)")
        resetUI()

        try await fileSystem.remove(temporaryDirectory)

        try await TuistTest.run(XcodeBuildBuildCommand.self, arguments)
        TuistTest.expectLogs("cacheable tasks (100%)")
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixture("generated_ios_app_with_catalyst")
    ) func ios_app_with_catalyst_caches_mac_catalyst_slice() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let mockedEnvironment = try #require(Environment.mocked)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])

        // When: Cache the binaries
        try await TuistTest.run(
            CacheCommand.self,
            ["--path", fixtureDirectory.pathString]
        )

        // Then: Generate the project with a focus on the App
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString, "App"])

        // Then: The Framework XCFramework should be linked in the App
        let xcworkspacePath = fixtureDirectory.appending(component: "App.xcworkspace")
        let xcodeprojPath = fixtureDirectory.appending(component: "App.xcodeproj")
        try TuistAcceptanceTest.expectXCFrameworkLinked("Framework", by: "App", xcodeprojPath: xcodeprojPath)

        // Then: Build the app for Mac Catalyst to verify it links correctly
        let arguments = [
            "-workspace", xcworkspacePath.pathString,
            "-scheme", "App",
            "-destination", "generic/platform=macOS,variant=Mac Catalyst",
            "-derivedDataPath", temporaryDirectory.pathString,
            "CODE_SIGN_IDENTITY=",
            "CODE_SIGNING_REQUIRED=NO",
            "CODE_SIGNING_ALLOWED=NO",
        ]
        try await TuistTest.run(XcodeBuildBuildCommand.self, arguments)
    }
}
