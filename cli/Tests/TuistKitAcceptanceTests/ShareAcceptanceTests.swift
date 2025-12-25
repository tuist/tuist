import Command
import FileSystem
import FileSystemTesting
import Foundation
import Path
import SnapshotTesting
import Testing
import TuistAcceptanceTesting
import TuistCore
import TuistSupport
import TuistTesting

@testable import TuistKit

struct ShareAcceptanceTests {
    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_ios_app_with_frameworks"),
        .withTestingSimulator("iPhone 16 Pro")
    )
    func share_ios_app_with_frameworks() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let simulator = try #require(Simulator.testing)

        // When: Build
        try await TuistTest.run(
            BuildCommand.self,
            ["App", "--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString]
        )
        resetUI()

        // When: Share
        try await TuistTest.run(
            ShareCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString]
        )
        let shareLink = try previewLink()
        resetUI()

        // When: Run
        try await TuistTest.run(
            RunCommand.self,
            [shareLink, "-destination", simulator.name]
        )
        #expect(
            ui()
                .contains("Launching App on \(simulator.name)") == true
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("xcode_app"),
    )
    func share_tuist_ipa() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let ipaPath = SwiftTestingHelper.fixturePath(path: try RelativePath(validating: "App.ipa"))

        // When
        try await TuistTest.run(
            ShareCommand.self,
            ["--path", fixtureDirectory.pathString, ipaPath.pathString]
        )

        // Then
        #expect(
            ui()
                .contains("Share Tuist with others") == true
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_ios_app_with_appclip"),
        .withTestingSimulator("iPhone 16")
    )
    func share_and_run_ios_app_with_appclip() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let simulator = try #require(Simulator.testing)

        // When: Build
        try await TuistTest.run(
            BuildCommand.self,
            ["App", "--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString]
        )
        resetUI()

        // When: Share
        try await TuistTest.run(
            ShareCommand.self,
            ["App", "--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString]
        )
        let shareLink = try previewLink("App")
        resetUI()

        // When: Run
        try await TuistTest.run(
            RunCommand.self,
            [shareLink, "-destination", simulator.name]
        )
        #expect(
            ui()
                .contains("Launching App on \(simulator.name)") == true
        )

        // When: Share AppClip1
        try await TuistTest.run(
            ShareCommand.self,
            ["AppClip1", "--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString]
        )
        let appClipShareLink = try previewLink("AppClip1")
        resetUI()

        // When: Run AppClip1
        try await TuistTest.run(
            RunCommand.self,
            [appClipShareLink, "-destination", simulator.name]
        )
        #expect(
            ui()
                .contains("Launching AppClip1 on \(simulator.name)") == true
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("xcode_app"),
        .withTestingSimulator("iPhone 16 Plus")
    )
    func share_and_run_xcode_app() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let simulator = try #require(Simulator.testing)

        // When: Build
        try await CommandRunner().run(arguments: [
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
        ]).pipedStream().awaitCompletion()

        // When: Share
        try await TuistTest.run(
            ShareCommand.self,
            [
                "App",
                "--platforms",
                "ios",
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                temporaryDirectory.pathString,
            ]
        )
        let previewLink = try previewLink()
        resetUI()

        // When: Run App
        try await TuistTest.run(
            RunCommand.self,
            [previewLink, "-destination", simulator.name]
        )
        #expect(
            ui()
                .contains("Launching App on \(simulator.name)") == true
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("xcode_app"),
        .withTestingSimulator("iPhone 16 Plus"),
    )
    func share_xcode_app_files() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let buildDirectory = fixtureDirectory.appending(component: "Build")
        let simulator = try #require(Simulator.testing)

        // When: Build
        try await CommandRunner().run(arguments: [
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
            "CONFIGURATION_BUILD_DIR=\(buildDirectory)",
        ]).pipedStream().awaitCompletion()

        // When: Share
        try await TuistTest.run(
            ShareCommand.self,
            [
                buildDirectory.appending(component: "App.app").pathString,
                "--platforms",
                "ios",
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                temporaryDirectory.pathString,
            ]
        )
        let previewLink = try previewLink()
        resetUI()

        // When: Run App
        try await TuistTest.run(
            RunCommand.self,
            [previewLink, "-destination", simulator.name]
        )
        #expect(
            ui()
                .contains("Launching App on \(simulator.name)") == true
        )
    }

    private func previewLink(_ displayName: String = "App") throws -> String {
        try #require(
            ui()
                .components(separatedBy: .newlines)
                .first(where: { $0.contains("Share \(displayName) with others") })?
                .components(separatedBy: .whitespaces)
                .last
        )
    }
}
