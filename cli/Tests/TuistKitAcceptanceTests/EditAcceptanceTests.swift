import Path
import Testing
import TuistAcceptanceTesting
import TuistSupport
import TuistTesting

@testable import TuistKit

struct EditAcceptanceTests {
    @Test(.withFixture("generated_ios_app_with_helpers"))
    func ios_app_with_helpers() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(EditCommand.self, ["--path", fixtureDirectory.pathString, "--permanent"])
        let workspacePath = try await TuistAcceptanceTest.xcworkspacePath(in: fixtureDirectory)
        try build(scheme: "Manifests", workspacePath: workspacePath)
    }

    @Test(.withFixture("generated_plugin"))
    func plugin() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(EditCommand.self, ["--path", fixtureDirectory.pathString, "--permanent"])
        let workspacePath = try await TuistAcceptanceTest.xcworkspacePath(in: fixtureDirectory)
        try build(scheme: "Plugins", workspacePath: workspacePath)
    }

    @Test(.withFixture("generated_app_with_plugins"))
    func app_with_plugins() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(EditCommand.self, ["--path", fixtureDirectory.pathString, "--permanent"])
        let workspacePath = try await TuistAcceptanceTest.xcworkspacePath(in: fixtureDirectory)
        try build(scheme: "Manifests", workspacePath: workspacePath)
        try build(scheme: "Plugins", workspacePath: workspacePath)
        try build(scheme: "LocalPlugin", workspacePath: workspacePath)
    }

    @Test(.withFixture("generated_app_with_spm_dependencies"))
    func app_with_spm_dependencies() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(EditCommand.self, ["--path", fixtureDirectory.pathString, "--permanent"])
        let workspacePath = try await TuistAcceptanceTest.xcworkspacePath(in: fixtureDirectory)
        try build(scheme: "Manifests", workspacePath: workspacePath)
    }

    @Test(.withFixture("generated_spm_package"))
    func spm_package() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(EditCommand.self, ["--path", fixtureDirectory.pathString, "--permanent"])
        let workspacePath = try await TuistAcceptanceTest.xcworkspacePath(in: fixtureDirectory)
        try build(scheme: "Manifests", workspacePath: workspacePath)
    }
}

private func build(scheme: String, workspacePath: AbsolutePath) throws {
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
