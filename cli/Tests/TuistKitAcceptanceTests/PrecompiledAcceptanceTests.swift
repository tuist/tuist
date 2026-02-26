import FileSystem
import FileSystemTesting
import Path
import Testing
import TuistBuildCommand
import TuistGenerateCommand
import TuistSupport
import TuistTesting

@testable import TuistKit

struct PrecompiledAcceptanceTests {
    @Test(.withFixture("generated_ios_app_with_static_frameworks"), .inTemporaryDirectory)
    func ios_app_with_static_frameworks() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }

    @Test(.withFixture("generated_ios_app_with_static_libraries"), .inTemporaryDirectory)
    func ios_app_with_static_libraries() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }

    @Test(.withFixture("generated_ios_app_with_transitive_framework"), .inTemporaryDirectory)
    func ios_app_with_transitive_framework() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["App", "--platform", "iOS", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
        try await expectProductContainsFrameworkWithArchitecture(
            framework: "Framework1",
            architecture: "arm64"
        )
        try await expectProductDoesNotContainHeaders(
            "App.app",
            destination: "Debug-iphonesimulator"
        )
        try await TuistTest.run(
            BuildCommand.self,
            [
                "Framework1-iOS",
                "--platform",
                "iOS",
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                derivedDataPath.pathString,
            ]
        )
        try await TuistTest.run(
            BuildCommand.self,
            [
                "Framework1-macOS",
                "--platform",
                "macOS",
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                derivedDataPath.pathString,
            ]
        )
        try await TuistTest.run(
            BuildCommand.self,
            [
                "Framework1Tests-iOS",
                "--platform",
                "iOS",
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                derivedDataPath.pathString,
            ]
        )
        try await TuistTest.run(
            BuildCommand.self,
            [
                "Framework1Tests-macOS",
                "--platform",
                "macOS",
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                derivedDataPath.pathString,
            ]
        )
        try await TuistTest.run(
            BuildCommand.self,
            [
                "StaticFramework1",
                "--platform",
                "iOS",
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                derivedDataPath.pathString,
            ]
        )
    }

    @Test(.withFixture("generated_ios_app_with_static_library_and_package"), .inTemporaryDirectory)
    func ios_app_with_static_library_and_package() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }

    @Test(.withFixture("generated_ios_app_with_xcframeworks"), .inTemporaryDirectory)
    func ios_app_with_xcframeworks() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(GenerateCommand.self, ["--no-open", "--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            BuildCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
        try await expectProductContainsFrameworkWithArchitecture(
            framework: "MyFramework",
            architecture: "x86_64"
        )
        try await expectProductDoesNotContainHeaders(
            "App.app",
            destination: "Debug-iphonesimulator"
        )
    }
}

private func productPath(for productName: String, destination: String) async throws -> AbsolutePath {
    let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
    let fileSystem = FileSystem()
    let products = try await fileSystem.glob(
        directory: derivedDataPath,
        include: ["Build/Products/\(destination)/\(productName)/"]
    ).collect()
    return try #require(products.first)
}

private func expectProductContainsFrameworkWithArchitecture(
    _ product: String = "App.app",
    destination: String = "Debug-iphonesimulator",
    framework: String,
    architecture: String,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let fileSystem = FileSystem()
    let productPath = try await productPath(
        for: product,
        destination: destination
    )

    guard let frameworkPath = try await fileSystem.glob(
        directory: productPath,
        include: ["**/Frameworks/\(framework).framework"]
    ).collect().first,
        try await fileSystem.exists(frameworkPath)
    else {
        Issue.record(
            "Framework \(framework) not found for product \(product) and destination \(destination)",
            sourceLocation: sourceLocation
        )
        return
    }

    let fileInfo = try await System.shared.runAndCollectOutput(
        [
            "file",
            frameworkPath.appending(component: framework).pathString,
        ]
    )
    #expect(fileInfo.standardOutput.contains(architecture), sourceLocation: sourceLocation)
}

private func expectProductDoesNotContainHeaders(
    _ product: String,
    destination: String,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let fileSystem = FileSystem()
    let productPath = try await productPath(for: product, destination: destination)
    let headers = try await fileSystem.glob(directory: productPath, include: ["**/*.h"]).collect()
    #expect(
        headers.isEmpty,
        "Product with name \(product) and destination \(destination) contains headers",
        sourceLocation: sourceLocation
    )
}
