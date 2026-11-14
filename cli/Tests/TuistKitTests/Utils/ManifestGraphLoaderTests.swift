import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import ProjectDescription
import Testing
import TuistConfigLoader
import TuistCore
import TuistLoader
import TuistPlugin
import TuistRootDirectoryLocator
import XcodeGraph
@testable import TuistKit
@testable import TuistTesting

struct ManifestGraphLoaderTests {
    /// The products that the workspace's projects link decide which packages can vend SwiftPM's macOS-only prebuilts, so
    /// the package graph loader needs them all, including those of local packages that Tuist maps into projects.
    @Test(.inTemporaryDirectory, .withMockedEnvironment(), .withMockedSwiftVersionProvider)
    func load_passesTheProductsThatProjectsAndLocalPackagesLinkToThePackageGraphLoader() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        try await fileSystem.makeDirectory(at: temporaryDirectory.appending(component: "App"))
        try await fileSystem.touch(temporaryDirectory.appending(components: "App", "Project.swift"))
        try await fileSystem.makeDirectory(at: temporaryDirectory.appending(components: "Feature", "Sources", "Feature"))

        let manifestLoader = MockManifestLoading()
        given(manifestLoader).validateHasRootManifest(at: .any).willReturn()
        given(manifestLoader).register(plugins: .any).willReturn()
        given(manifestLoader).loadWorkspace(at: .any, disableSandbox: .any)
            .willReturn(Workspace(name: "Workspace", projects: ["App", "Feature"]))
        given(manifestLoader).loadProject(at: .any, disableSandbox: .any).willReturn(
            Project(name: "App", targets: [
                .target(
                    name: "App",
                    destinations: .macOS,
                    product: .commandLineTool,
                    bundleId: "dev.tuist.app",
                    dependencies: [
                        .external(name: "Formatting"),
                        .externalWithStatus(name: "Highlighting", status: .optional),
                    ]
                ),
            ])
        )
        given(manifestLoader).manifests(at: .any).willProduce { path in
            path.basename == "Feature" ? [.package] : [.project]
        }
        given(manifestLoader).loadPackage(at: .any, disableSandbox: .any).willReturn(
            PackageInfo(
                name: "Feature",
                products: [.init(name: "Feature", type: .library(.automatic), targets: ["Feature"])],
                targets: [
                    .init(
                        name: "Feature",
                        path: nil,
                        url: nil,
                        sources: nil,
                        resources: [],
                        exclude: [],
                        dependencies: [
                            .product(
                                name: "CasePathsMacrosSupport",
                                package: "swift-case-paths",
                                moduleAliases: nil,
                                condition: nil
                            ),
                        ],
                        publicHeadersPath: nil,
                        type: .regular,
                        settings: [],
                        checksum: nil
                    ),
                ],
                traits: nil,
                dependencies: [],
                platforms: [.init(platformName: "macos", version: "14.0", options: [])],
                cLanguageStandard: nil,
                cxxLanguageStandard: nil,
                swiftLanguageVersions: nil,
                toolsVersion: "5.9.0"
            )
        )
        let configLoader = MockConfigLoading()
        given(configLoader).loadConfig(path: .any).willReturn(.test())
        let rootDirectoryLocator = MockRootDirectoryLocating()
        given(rootDirectoryLocator).locate(from: .any).willReturn(temporaryDirectory)
        let manifestFilesLocator = MockManifestFilesLocating()
        given(manifestFilesLocator).locatePackageManifest(at: .any)
            .willReturn(temporaryDirectory.appending(components: "Tuist", "Package.swift"))
        let subject = ManifestGraphLoader(
            configLoader: configLoader,
            manifestLoader: manifestLoader,
            recursiveManifestLoader: RecursiveManifestLoader(
                manifestLoader: manifestLoader,
                rootDirectoryLocator: rootDirectoryLocator
            ),
            converter: ManifestModelConverter(manifestLoader: manifestLoader),
            graphLoader: GraphLoader(),
            pluginsService: MockPluginService(),
            swiftPackageManagerGraphLoader: SwiftPackageManagerGraphLoaderSpy(),
            graphLoaderLinter: CircularDependencyLinter(),
            manifestLinter: ManifestLinter(),
            workspaceMapper: SequentialWorkspaceMapper(mappers: []),
            graphMapper: SequentialGraphMapper([]),
            packageSettingsLoader: MockPackageSettingsLoader(),
            manifestFilesLocator: manifestFilesLocator
        )

        let error = await #expect(throws: CapturedExternalDependencyNames.self) {
            try await subject.load(path: temporaryDirectory, disableSandbox: true)
        }

        #expect(error?.names == ["Formatting", "Highlighting", "CasePathsMacrosSupport"])
    }
}

private struct CapturedExternalDependencyNames: Error {
    let names: Set<String>
}

/// Stops the load once the package graph loader is reached, reporting the products it received.
private struct SwiftPackageManagerGraphLoaderSpy: SwiftPackageManagerGraphLoading {
    func load(
        packagePath _: AbsolutePath,
        packageSettings _: TuistCore.PackageSettings,
        disableSandbox _: Bool,
        swiftPackageManagerArguments _: [String],
        externalDependencyNames: Set<String>
    ) async throws -> (TuistLoader.DependenciesGraph, [LintingIssue]) {
        throw CapturedExternalDependencyNames(names: externalDependencyNames)
    }
}
