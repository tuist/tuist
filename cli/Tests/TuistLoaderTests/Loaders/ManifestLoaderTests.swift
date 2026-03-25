import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistConstants
import XcodeGraph

@testable import TuistLoader
@testable import TuistSupport
@testable import TuistTesting

@Suite(.withMockedDependencies()) struct ManifestLoaderTests {
    private let subject: ManifestLoader
    private let fileSystem: FileSysteming

    init() {
        fileSystem = FileSystem()
        subject = ManifestLoader()
    }

    @Test(.inTemporaryDirectory) func loadConfig() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let content = """
        import ProjectDescription
        let config = Config()
        """
        let manifestPath = temporaryPath.appending(component: Manifest.config.fileName(temporaryPath))
        try content.write(to: manifestPath.url, atomically: true, encoding: .utf8)

        _ = try await subject.loadConfig(at: temporaryPath)
    }

    @Test(.inTemporaryDirectory) func loadPlugin() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let content = """
        import ProjectDescription
        let plugin = Plugin(name: "TestPlugin")
        """
        let manifestPath = temporaryPath.appending(component: Manifest.plugin.fileName(temporaryPath))
        try content.write(to: manifestPath.url, atomically: true, encoding: .utf8)

        _ = try await subject.loadPlugin(at: temporaryPath)
    }

    @Test(.inTemporaryDirectory) func loadProject() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let content = """
        import ProjectDescription
        let project = Project(name: "tuist")
        """
        let manifestPath = temporaryPath.appending(component: Manifest.project.fileName(temporaryPath))
        try content.write(to: manifestPath.url, atomically: true, encoding: .utf8)

        let got = try await subject.loadProject(at: temporaryPath, disableSandbox: true)
        #expect(got.name == "tuist")
    }

    @Test(.inTemporaryDirectory) func loadPackage() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let content = """
        // swift-tools-version: 5.9
        import PackageDescription

        #if TUIST
        import ProjectDescription

        let packageSettings = PackageSettings(
            platforms: [.iOS, .watchOS]
        )

        #endif

        let package = Package(
            name: "tuist",
            products: [
                .executable(name: "tuist", targets: ["tuist"]),
            ],
            dependencies: [],
            targets: [
                .target(
                    name: "tuist",
                    dependencies: []
                ),
            ]
        )

        """
        let manifestPath = temporaryPath.appending(component: Manifest.package.fileName(temporaryPath))
        try await fileSystem.makeDirectory(at: temporaryPath.appending(component: Constants.tuistDirectoryName))
        try content.write(to: manifestPath.url, atomically: true, encoding: .utf8)

        let got = try await subject.loadPackage(at: manifestPath.parentDirectory, disableSandbox: true)
        #expect(got.name == "tuist")
    }

    @Test(.inTemporaryDirectory) func loadPackageSettings() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let content = """
        // swift-tools-version: 5.9
        import PackageDescription

        #if TUIST
        import ProjectDescription

        let packageSettings = PackageSettings(
            targetSettings: ["TargetA": ["OTHER_LDFLAGS": "-ObjC"]]
        )

        #endif

        let package = Package(
            name: "PackageName",
            dependencies: [
                .package(url: "https://github.com/Alamofire/Alamofire", exact: "5.8.0"),
            ]
        )

        """
        let manifestPath = temporaryPath.appending(component: Manifest.package.fileName(temporaryPath))
        try await fileSystem.makeDirectory(at: temporaryPath.appending(component: Constants.tuistDirectoryName))
        try content.write(to: manifestPath.url, atomically: true, encoding: .utf8)

        let got = try await subject.loadPackageSettings(at: temporaryPath, disableSandbox: true)
        #expect(got == .init(targetSettings: ["TargetA": .settings(base: ["OTHER_LDFLAGS": "-ObjC"])]))
    }

    @Test(.inTemporaryDirectory) func loadPackageSettings_without_package_settings() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let content = """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "PackageName",
            dependencies: []
        )

        """
        let manifestPath = temporaryPath.appending(component: Manifest.package.fileName(temporaryPath))
        try await fileSystem.makeDirectory(at: temporaryPath.appending(component: Constants.tuistDirectoryName))
        try content.write(to: manifestPath.url, atomically: true, encoding: .utf8)

        let got = try await subject.loadPackageSettings(at: temporaryPath, disableSandbox: true)
        #expect(got == .init())
    }

    @Test(.inTemporaryDirectory) func loadWorkspace() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let content = """
        import ProjectDescription
        let workspace = Workspace(name: "tuist", projects: [])
        """
        let manifestPath = temporaryPath.appending(component: Manifest.workspace.fileName(temporaryPath))
        try content.write(to: manifestPath.url, atomically: true, encoding: .utf8)

        let got = try await subject.loadWorkspace(at: temporaryPath, disableSandbox: true)
        #expect(got.name == "tuist")
    }

    @Test(.inTemporaryDirectory) func loadTemplate() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory).appending(component: "folder")
        try await fileSystem.makeDirectory(at: temporaryPath)
        let content = """
        import ProjectDescription

        let template = Template(
            description: "Template description",
            items: []
        )
        """
        let manifestPath = temporaryPath.appending(component: "folder.swift")
        try content.write(to: manifestPath.url, atomically: true, encoding: .utf8)

        let got = try await subject.loadTemplate(at: temporaryPath)
        #expect(got.description == "Template description")
    }

    @Test(.inTemporaryDirectory) func load_invalidFormat() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let content = """
        import ABC
        let project
        """
        let manifestPath = temporaryPath.appending(component: Manifest.project.fileName(temporaryPath))
        try content.write(to: manifestPath.url, atomically: true, encoding: .utf8)

        var _error: Error?
        do {
            _ = try await subject.loadProject(at: temporaryPath, disableSandbox: false)
        } catch {
            _error = error
        }
        #expect(_error != nil)
    }

    @Test(.inTemporaryDirectory) func load_missingManifest() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        await #expect(throws: ManifestLoaderError.manifestNotFound(.project, temporaryPath)) {
            try await self.subject.loadProject(at: temporaryPath, disableSandbox: false)
        }
    }

    @Test(.inTemporaryDirectory) func manifestsAt() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.touch(temporaryPath.appending(component: "Project.swift"))
        try await fileSystem.touch(temporaryPath.appending(component: "Workspace.swift"))
        try await fileSystem.touch(temporaryPath.appending(component: "Config.swift"))

        let got = try await subject.manifests(at: temporaryPath)
        #expect(got.contains(.project))
        #expect(got.contains(.workspace))
        #expect(got.contains(.config))
    }

    @Test(.inTemporaryDirectory) func manifestLoadError() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let configPath = temporaryPath.appending(component: "Config.swift")
        try await fileSystem.touch(configPath)
        let data = try Data(contentsOf: configPath.url)

        await #expect(throws: ManifestLoaderError.manifestLoadingFailed(
            path: temporaryPath.appending(component: "Config.swift"),
            data: data,
            context: """
            The encoded data for the manifest is corrupted.
            The given data was not valid JSON.
            """
        )) {
            try await self.subject.loadConfig(at: temporaryPath)
        }
    }

    @Test(.inTemporaryDirectory) func validate_projectExists() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        try await fileSystem.touch(path.appending(component: "Project.swift"))
        try await subject.validateHasRootManifest(at: path)
    }

    @Test(.inTemporaryDirectory) func validate_workspaceExists() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        try await fileSystem.touch(path.appending(component: "Workspace.swift"))
        try await subject.validateHasRootManifest(at: path)
    }

    @Test(.inTemporaryDirectory) func validate_packageExists() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        try await fileSystem.touch(path.appending(component: "Package.swift"))
        try await subject.validateHasRootManifest(at: path)
    }

    @Test(.inTemporaryDirectory) func validate_manifestDoesNotExist() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        await #expect(throws: ManifestLoaderError.manifestNotFound(path)) {
            try await self.subject.validateHasRootManifest(at: path)
        }
    }

    @Test(.inTemporaryDirectory) func hasRootManifest_projectExists() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        try await fileSystem.makeDirectory(at: path)
        try await fileSystem.touch(path.appending(component: "Project.swift"))
        let got = try await subject.hasRootManifest(at: path)
        #expect(got)
    }

    @Test(.inTemporaryDirectory) func hasRootManifest_workspaceExists() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        try await fileSystem.touch(path.appending(component: "Workspace.swift"))
        let got = try await subject.hasRootManifest(at: path)
        #expect(got)
    }

    @Test(.inTemporaryDirectory) func hasRootManifest_packageExists() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        try await fileSystem.touch(path.appending(component: "Package.swift"))
        let got = try await subject.hasRootManifest(at: path)
        #expect(got)
    }

    @Test(.inTemporaryDirectory) func hasRootManifest_manifestDoesNotExist() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "App")
        let got = try await subject.hasRootManifest(at: path)
        #expect(!got)
    }
}
