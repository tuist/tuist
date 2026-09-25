import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistConfigLoader
import TuistConstants
import TuistCore
import TuistEnvironmentTesting
import TuistLoader
import XcodeGraph

@testable import TuistKit
@testable import TuistTesting

struct StaticXCFrameworkModuleMapGraphMapperPlatformConditionTests {
    private let subject: StaticXCFrameworkModuleMapGraphMapper
    private let manifestFilesLocator = MockManifestFilesLocating()

    init() {
        let configLoader = MockConfigLoading()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .generated(.test())))
        subject = StaticXCFrameworkModuleMapGraphMapper(
            manifestFilesLocator: manifestFilesLocator,
            configLoader: configLoader
        )
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func map_when_linked_directly_under_a_matching_platform_condition() async throws {
        // Given
        let fixture = try await makeFixture()
        let dynamicFramework: GraphDependency = .testXCFramework(
            path: fixture.temporaryDirectory.appending(component: "Renderer.xcframework")
        )
        let appDependency = GraphDependency.target(name: "App", path: fixture.projectPath)
        let graph: Graph = .test(
            name: "App",
            path: fixture.projectPath,
            projects: [
                fixture.projectPath: .test(
                    path: fixture.projectPath,
                    targets: [.test(name: "App"), .test(name: "Consumer")]
                ),
            ],
            dependencies: [
                appDependency: [.target(name: "Consumer", path: fixture.projectPath), fixture.nativeRenderer],
                .target(name: "Consumer", path: fixture.projectPath): [dynamicFramework],
                dynamicFramework: [fixture.nativeRenderer],
            ],
            dependencyConditions: [
                GraphEdge(from: appDependency, to: fixture.nativeRenderer): try #require(PlatformCondition.when([.ios])),
            ]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        #expect(gotGraph == graph.withTargetSettings(["App": [:], "Consumer": [:]], at: fixture.projectPath))
        #expect(gotSideEffects.isEmpty)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func map_when_processed_by_a_static_target_through_a_cached_static_xcframework() async throws {
        // Given
        let fixture = try await makeFixture()
        let cachedStaticWrapper: GraphDependency = .testXCFramework(
            path: fixture.temporaryDirectory.appending(component: "NativeRendererKit.xcframework"),
            linking: .static,
            swiftModules: [
                fixture.temporaryDirectory.appending(
                    components: "NativeRendererKit.xcframework",
                    "NativeRendererKit.swiftmodule"
                ),
            ]
        )
        let cachedDynamicFramework: GraphDependency = .testXCFramework(
            path: fixture.temporaryDirectory.appending(component: "Renderer.xcframework")
        )
        let graph: Graph = .test(
            name: "App",
            path: fixture.projectPath,
            projects: [
                fixture.projectPath: .test(
                    path: fixture.projectPath,
                    targets: [
                        .test(name: "Canvas", product: .staticFramework),
                        .test(name: "Palette", product: .staticFramework),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "Canvas", path: fixture.projectPath): [cachedStaticWrapper],
                cachedStaticWrapper: [fixture.nativeRenderer],
                .target(name: "Palette", path: fixture.projectPath): [cachedDynamicFramework],
                cachedDynamicFramework: [cachedStaticWrapper],
            ],
            dependencyConditions: [
                GraphEdge(from: cachedStaticWrapper, to: fixture.nativeRenderer): try #require(PlatformCondition.when([.ios])),
            ]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        #expect(gotGraph == graph.withTargetSettings(
            [
                "Canvas": [:],
                "Palette": [
                    "FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]": [
                        "$(inherited)",
                        "\"$(SRCROOT)/../NativeRendererKit.xcframework/test\"",
                    ],
                ],
            ],
            at: fixture.projectPath
        ))
        #expect(gotSideEffects.isEmpty)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func map_when_linked_directly_only_for_mac_catalyst() async throws {
        // Given
        let fixture = try await makeFixture()
        let dynamicFramework: GraphDependency = .testXCFramework(
            path: fixture.temporaryDirectory.appending(component: "Renderer.xcframework")
        )
        let appDependency = GraphDependency.target(name: "App", path: fixture.projectPath)
        let graph: Graph = .test(
            name: "App",
            path: fixture.projectPath,
            projects: [
                fixture.projectPath: .test(
                    path: fixture.projectPath,
                    targets: [
                        .test(name: "App", destinations: [.iPhone, .macCatalyst]),
                        .test(name: "Consumer"),
                    ]
                ),
            ],
            dependencies: [
                appDependency: [.target(name: "Consumer", path: fixture.projectPath), fixture.nativeRenderer],
                .target(name: "Consumer", path: fixture.projectPath): [dynamicFramework],
                dynamicFramework: [fixture.nativeRenderer],
            ],
            dependencyConditions: [
                GraphEdge(from: appDependency, to: fixture.nativeRenderer): try #require(PlatformCondition.when([.catalyst])),
            ]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let settings = fixture.vendorModuleMapSettings(sdkCondition: nil)
        #expect(gotGraph == graph.withTargetSettings(["App": settings, "Consumer": settings], at: fixture.projectPath))
        #expect(gotSideEffects == fixture.derivedModuleMapSideEffects)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func map_when_the_module_map_is_published_only_on_some_of_the_consumer_platforms() async throws {
        // Given
        let fixture = try await makeFixture()
        let dynamicFramework: GraphDependency = .testXCFramework(
            path: fixture.temporaryDirectory.appending(component: "Renderer.xcframework")
        )
        let canvasDependency = GraphDependency.target(name: "Canvas", path: fixture.projectPath)
        let graph: Graph = .test(
            name: "App",
            path: fixture.projectPath,
            projects: [
                fixture.projectPath: .test(
                    path: fixture.projectPath,
                    targets: [
                        .test(name: "Canvas", destinations: [.iPhone, .mac]),
                        .test(name: "Consumer", destinations: [.iPhone, .mac]),
                    ]
                ),
            ],
            dependencies: [
                canvasDependency: [fixture.nativeRenderer],
                .target(name: "Consumer", path: fixture.projectPath): [dynamicFramework],
                dynamicFramework: [fixture.nativeRenderer],
            ],
            dependencyConditions: [
                GraphEdge(from: canvasDependency, to: fixture.nativeRenderer): try #require(PlatformCondition.when([.ios])),
            ]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        #expect(gotGraph == graph.withTargetSettings(
            ["Canvas": [:], "Consumer": fixture.vendorModuleMapSettings(sdkCondition: "sdk=macosx*")],
            at: fixture.projectPath
        ))
        #expect(gotSideEffects == fixture.derivedModuleMapSideEffects)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func map_when_the_module_map_is_published_for_ios_and_the_consumer_also_builds_for_mac_catalyst() async throws {
        // Given
        let fixture = try await makeFixture()
        let dynamicFramework: GraphDependency = .testXCFramework(
            path: fixture.temporaryDirectory.appending(component: "Renderer.xcframework")
        )
        let graph: Graph = .test(
            name: "App",
            path: fixture.projectPath,
            projects: [
                fixture.projectPath: .test(
                    path: fixture.projectPath,
                    targets: [
                        .test(name: "Canvas", destinations: [.iPhone]),
                        .test(name: "Consumer", destinations: [.iPhone, .macCatalyst]),
                    ]
                ),
            ],
            dependencies: [
                .target(name: "Canvas", path: fixture.projectPath): [fixture.nativeRenderer],
                .target(name: "Consumer", path: fixture.projectPath): [dynamicFramework],
                dynamicFramework: [fixture.nativeRenderer],
            ]
        )

        // When
        let (gotGraph, gotSideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        #expect(gotGraph == graph.withTargetSettings(
            ["Canvas": [:], "Consumer": fixture.vendorModuleMapSettings(sdkCondition: "sdk=macosx*")],
            at: fixture.projectPath
        ))
        #expect(gotSideEffects == fixture.derivedModuleMapSideEffects)
    }

    private struct Fixture {
        let temporaryDirectory: AbsolutePath
        let projectPath: AbsolutePath
        let nativeRenderer: GraphDependency

        var derivedHeadersDirectory: AbsolutePath {
            projectPath.appending(
                components: [
                    Constants.tuistDirectoryName,
                    Constants.SwiftPackageManager.packageBuildDirectoryName,
                    Constants.DerivedDirectory.dependenciesDerivedDirectory,
                    Constants.DerivedDirectory.dependenciesXCFrameworkDirectory,
                    "NativeRenderer",
                    "Headers",
                ]
            )
        }

        var derivedModuleMapSideEffects: [SideEffectDescriptor] {
            [
                .directory(DirectoryDescriptor(path: derivedHeadersDirectory)),
                .file(
                    FileDescriptor(
                        path: derivedHeadersDirectory.appending(component: "module.modulemap"),
                        contents: "modulemap".data(using: .utf8)
                    )
                ),
            ]
        }

        func vendorModuleMapSettings(sdkCondition: String?) -> SettingsDictionary {
            let key: (String) -> String = { name in sdkCondition.map { "\(name)[\($0)]" } ?? name }
            let inherited = sdkCondition == nil ? [] : ["$(inherited)"]
            let moduleMapFlag =
                "-fmodule-map-file=\"$(SRCROOT)/Tuist/.build/tuist-derived/XCFrameworks/NativeRenderer/Headers/module.modulemap\""
            return [
                key("OTHER_SWIFT_FLAGS"): .array(inherited + ["-Xcc", moduleMapFlag]),
                key("OTHER_C_FLAGS"): .array(inherited + [moduleMapFlag]),
                key("HEADER_SEARCH_PATHS"): .array(
                    inherited + ["\"$(SRCROOT)/Tuist/.build/tuist-derived/XCFrameworks/NativeRenderer/Headers\""]
                ),
            ]
        }
    }

    /// A static library xcframework with a flat `Headers/module.modulemap`, next to a project that
    /// resolves its dependencies through `Tuist/Package.swift`.
    private func makeFixture() async throws -> Fixture {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "Project")
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(
                projectPath.appending(components: Constants.tuistDirectoryName, Constants.SwiftPackageManager.packageSwiftName)
            )
        let nativeRendererPath = temporaryDirectory.appending(component: "NativeRenderer.xcframework")
        let headersPath = nativeRendererPath.appending(components: "ios-arm64", "Headers")
        let fileSystem = FileSystem()
        try await fileSystem.makeDirectory(at: headersPath)
        try await fileSystem.writeText("modulemap", at: headersPath.appending(component: "module.modulemap"))
        return Fixture(
            temporaryDirectory: temporaryDirectory,
            projectPath: projectPath,
            nativeRenderer: .testXCFramework(
                path: nativeRendererPath,
                infoPlist: .test(libraries: [.test(path: try RelativePath(validating: "libnative_renderer.a"))]),
                linking: .static,
                moduleMaps: [headersPath.appending(component: "module.modulemap")]
            )
        )
    }
}

extension Graph {
    /// The graph with each named target's base settings replaced, as the mapper writes them.
    fileprivate func withTargetSettings(_ settingsByTarget: [String: SettingsDictionary], at projectPath: AbsolutePath) -> Graph {
        guard var project = projects[projectPath] else { return self }
        project.targets = project.targets.mapValues { target in
            guard let settings = settingsByTarget[target.name] else { return target }
            var target = target
            target.settings = .test(base: settings)
            return target
        }
        var graph = self
        graph.projects[projectPath] = project
        return graph
    }
}
