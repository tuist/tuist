import FileSystem
import Foundation
import XcodeGraph
import Testing
import ServiceContextModule

@testable import TuistLoader
@testable import TuistSupport
@testable import TuistSupportTesting

struct ManifestLoaderTests {
    private var subject: ManifestLoader = ManifestLoader()
    private var fileSystem: FileSysteming = FileSystem()

    @Test(.mocked, .temporaryDirectory) func test_loadConfig() async throws {
        // Given
        let temporaryPath = ServiceContext.current!.temporaryDirectory!
        let content = """
        import ProjectDescription
        let config = Config()
        """

        let manifestPath = temporaryPath.appending(component: Manifest.config.fileName(temporaryPath))
        try content.write(
            to: manifestPath.url,
            atomically: true,
            encoding: .utf8
        )

        // When
        _ = try await subject.loadConfig(at: temporaryPath)
    }

    @Test(.mocked, .temporaryDirectory) func test_loadPlugin() async throws {
        // Given
        let temporaryPath = ServiceContext.current!.temporaryDirectory!
        let content = """
        import ProjectDescription
        let plugin = Plugin(name: "TestPlugin")
        """

        let manifestPath = temporaryPath.appending(component: Manifest.plugin.fileName(temporaryPath))
        try content.write(to: manifestPath.url, atomically: true, encoding: .utf8)

        // When
        _ = try await subject.loadPlugin(at: temporaryPath)
    }

    @Test(.mocked, .temporaryDirectory) func test_loadProject() async throws {
        // Given
        let temporaryPath = ServiceContext.current!.temporaryDirectory!
        let content = """
        import ProjectDescription
        let project = Project(name: "tuist")
        """

        let manifestPath = temporaryPath.appending(component: Manifest.project.fileName(temporaryPath))
        try content.write(
            to: manifestPath.url,
            atomically: true,
            encoding: .utf8
        )

        // When
        let got = try await subject.loadProject(at: temporaryPath)

        // Then
        #expect(got.name == "tuist")
    }

    @Test(.mocked, .temporaryDirectory) func test_loadPackage() async throws {
        // Given
        let temporaryPath = ServiceContext.current!.temporaryDirectory!
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

        let manifestPath = temporaryPath.appending(
            component: Manifest.package.fileName(temporaryPath)
        )
        try FileHandler.shared.createFolder(temporaryPath.appending(component: Constants.tuistDirectoryName))
        try content.write(
            to: manifestPath.url,
            atomically: true,
            encoding: .utf8
        )

        // When
        let got = try await subject.loadPackage(at: manifestPath.parentDirectory)

        // Then
        #expect(
            got ==
            .test(
                name: "tuist",
                products: [
                    PackageInfo.Product(name: "tuist", type: .executable, targets: ["tuist"]),
                ],
                targets: [
                    PackageInfo.Target(
                        name: "tuist",
                        path: nil,
                        url: nil,
                        sources: nil,
                        resources: [],
                        exclude: [],
                        dependencies: [],
                        publicHeadersPath: nil,
                        type: .regular,
                        settings: [],
                        checksum: nil,
                        packageAccess: true
                    ),
                ]
            )
        )
    }

    @Test(.mocked, .temporaryDirectory) func test_loadPackageSettings() async throws {
        // Given
        let temporaryPath = ServiceContext.current!.temporaryDirectory!
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

        let manifestPath = temporaryPath.appending(
            component: Manifest.package.fileName(temporaryPath)
        )
        try FileHandler.shared.createFolder(temporaryPath.appending(component: Constants.tuistDirectoryName))
        try content.write(
            to: manifestPath.url,
            atomically: true,
            encoding: .utf8
        )

        // When
        let got = try await subject.loadPackageSettings(at: temporaryPath)

        // Then
        #expect(
            got ==
            .init(
                targetSettings: [
                    "TargetA": .settings(base: [
                        "OTHER_LDFLAGS": "-ObjC",
                    ]),
                ]
            )
        )
    }

    @Test(.mocked, .temporaryDirectory) func test_loadPackageSettings_without_package_settings() async throws {
        // Given
        let temporaryPath = ServiceContext.current!.temporaryDirectory!
        let content = """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "PackageName",
            dependencies: []
        )

        """

        let manifestPath = temporaryPath.appending(
            component: Manifest.package.fileName(temporaryPath)
        )
        try FileHandler.shared.createFolder(temporaryPath.appending(component: Constants.tuistDirectoryName))
        try content.write(
            to: manifestPath.url,
            atomically: true,
            encoding: .utf8
        )

        // When
        let got = try await subject.loadPackageSettings(at: temporaryPath)

        // Then
        #expect(
            got ==
            .init()
        )
    }

    @Test(.mocked, .temporaryDirectory) func test_loadWorkspace() async throws {
        // Given
        let temporaryPath = ServiceContext.current!.temporaryDirectory!
        let content = """
        import ProjectDescription
        let workspace = Workspace(name: "tuist", projects: [])
        """

        let manifestPath = temporaryPath.appending(component: Manifest.workspace.fileName(temporaryPath))
        try content.write(
            to: manifestPath.url,
            atomically: true,
            encoding: .utf8
        )

        // When
        let got = try await subject.loadWorkspace(at: temporaryPath)

        // Then
        #expect(got.name == "tuist")
    }

    @Test(.mocked, .temporaryDirectory) func test_loadTemplate() async throws {
        // Given
        let temporaryPath = ServiceContext.current!.temporaryDirectory!.appending(component: "folder")
        try await fileSystem.makeDirectory(at: temporaryPath)
        let content = """
        import ProjectDescription

        let template = Template(
            description: "Template description",
            items: []
        )
        """

        let manifestPath = temporaryPath.appending(component: "folder.swift")
        try content.write(
            to: manifestPath.url,
            atomically: true,
            encoding: .utf8
        )

        // When
        let got = try await subject.loadTemplate(at: temporaryPath)

        // Then
        #expect(got.description == "Template description")
    }

    @Test(.mocked, .temporaryDirectory) func test_load_invalidFormat() async throws {
        // Given
        let temporaryPath = ServiceContext.current!.temporaryDirectory!
        let content = """
        import ABC
        let project
        """

        let manifestPath = temporaryPath.appending(component: Manifest.project.fileName(temporaryPath))
        try content.write(
            to: manifestPath.url,
            atomically: true,
            encoding: .utf8
        )

        // When / Then
        await #expect(throws: Error.self, performing: { try await subject.loadProject(at: temporaryPath) })
    }

    @Test(.mocked, .temporaryDirectory) func test_load_missingManifest() async throws {
        let temporaryPath = ServiceContext.current!.temporaryDirectory!
        await #expect(throws: ManifestLoaderError.manifestNotFound(.project, temporaryPath), performing: { try await self.subject.loadProject(at: temporaryPath) })
    }

    @Test(.mocked, .temporaryDirectory) func test_manifestsAt() async throws {
        // Given
        let temporaryPath = ServiceContext.current!.temporaryDirectory!
        try await fileSystem.touch(temporaryPath.appending(component: "Project.swift"))
        try await fileSystem.touch(temporaryPath.appending(component: "Workspace.swift"))
        try await fileSystem.touch(temporaryPath.appending(component: "Config.swift"))

        // When
        let got = try await subject.manifests(at: temporaryPath)

        // Then
        #expect(got.contains(.project) == true)
        #expect(got.contains(.workspace) == true)
        #expect(got.contains(.config) == true)
    }

    @Test(.mocked, .temporaryDirectory) func test_manifestLoadError() async throws {
        // Given
        let temporaryPath = ServiceContext.current!.temporaryDirectory!
        let configPath = temporaryPath.appending(component: "Config.swift")
        try await fileSystem.touch(configPath)
        let data = try await fileSystem.readFile(at: configPath)

        // When
        await #expect(throws: ManifestLoaderError.manifestLoadingFailed(
            path: temporaryPath.appending(component: "Config.swift"),
            data: data,
            context: """
            The encoded data for the manifest is corrupted.
            The given data was not valid JSON.
            """
        ), performing: { try await self.subject.loadConfig(at: temporaryPath) })
    }

    @Test(.mocked, .temporaryDirectory) func test_validate_projectExists() async throws {
        // Given
        let path = ServiceContext.current!.temporaryDirectory!.appending(component: "App")
        try await fileSystem.makeDirectory(at: path)
        try await fileSystem.touch(
            path.appending(component: "Project.swift")
        )

        // When / Then
        try await subject.validateHasRootManifest(at: path)
    }

    @Test(.mocked, .temporaryDirectory) func test_validate_workspaceExists() async throws {
        // Given
        let path = ServiceContext.current!.temporaryDirectory!.appending(component: "App")
        try await fileSystem.makeDirectory(at: path)
        try await fileSystem.touch(
            path.appending(component: "Workspace.swift")
        )

        // When / Then
        try await subject.validateHasRootManifest(at: path)
    }

    @Test(.mocked, .temporaryDirectory) func test_validate_packageExists() async throws {
        // Given
        let path = ServiceContext.current!.temporaryDirectory!.appending(component: "App")
        try await fileSystem.touch(
            path.appending(component: "Package.swift")
        )

        // When / Then
        try await subject.validateHasRootManifest(at: path)
    }

    @Test(.mocked, .temporaryDirectory) func test_validate_manifestDoesNotExist() async throws {
        // Given
        let path = ServiceContext.current!.temporaryDirectory!.appending(component: "App")

        // When / Then
        await #expect(throws: ManifestLoaderError.manifestNotFound(path), performing: { try await subject.validateHasRootManifest(at: path) })
    }

    @Test(.mocked, .temporaryDirectory) func test_hasRootManifest_projectExists() async throws {
        // Given
        let path = ServiceContext.current!.temporaryDirectory!.appending(component: "App")
        try await fileSystem.makeDirectory(at: path)
        try await fileSystem.touch(
            path.appending(component: "Project.swift")
        )

        // When
        let got = try await subject.hasRootManifest(at: path)

        // Then
        #expect(got == true)
    }

    @Test(.mocked, .temporaryDirectory) func test_hasRootManifest_workspaceExists() async throws {
        // Given
        let path = ServiceContext.current!.temporaryDirectory!.appending(component: "App")
        try await fileSystem.touch(
            path.appending(component: "Workspace.swift")
        )

        // When
        let got = try await subject.hasRootManifest(at: path)

        // Then
        #expect(got == true)
    }

    @Test(.mocked, .temporaryDirectory) func test_hasRootManifest_packageExists() async throws {
        // Given
        let path = ServiceContext.current!.temporaryDirectory!.appending(component: "App")
        try await fileSystem.touch(
            path.appending(component: "Package.swift")
        )

        // When
        let got = try await subject.hasRootManifest(at: path)

        // Then
        #expect(got == true)
    }

    @Test(.mocked, .temporaryDirectory) func test_hasRootManifest_manifestDoesNotExist() async throws {
        // Given
        let path = ServiceContext.current!.temporaryDirectory!.appending(component: "App")

        // When
        let got = try await subject.hasRootManifest(at: path)

        // Then
        #expect(got == false)
    }
}
