import FileSystem
import Foundation
import Mockable
import Path
import Testing
import XcodeGraph
import XcodeProj
@testable import XcodeGraphMapper

@Suite
struct XcodeGraphMapperTests {
    private let fileSystem = FileSystem()

    @Test("Maps a single project into a workspace graph")
    func singleProjectGraph() async throws {
        // Given
        let pbxProj = PBXProj()
        let debug: XCBuildConfiguration = .testDebug().add(to: pbxProj)
        let releaseConfig: XCBuildConfiguration = .testRelease().add(to: pbxProj)
        let configurationList: XCConfigurationList = .test(buildConfigurations: [debug, releaseConfig])
            .add(to: pbxProj)

        let xcodeProj = try await XcodeProj.test(
            projectName: "SingleProject",
            configurationList: configurationList,
            pbxProj: pbxProj
        )

        let sourceFile = try PBXFileReference.test(
            path: "ViewController.swift",
            lastKnownFileType: "sourcecode.swift"
        ).add(to: pbxProj).addToMainGroup(in: pbxProj)

        let buildFile = PBXBuildFile(file: sourceFile).add(to: pbxProj)
        let sourcesPhase = PBXSourcesBuildPhase(files: [buildFile]).add(to: pbxProj)

        // Add a single target to the project
        try PBXNativeTarget.test(
            name: "App",
            buildConfigurationList: configurationList,
            buildPhases: [sourcesPhase],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        let projectPath = xcodeProj.projectPath
        try xcodeProj.write(path: try #require(xcodeProj.path))
        let mapper = XcodeGraphMapper()
        // When
        let graph = try await mapper.buildGraph(from: .project(xcodeProj))

        // Then
        #expect(graph.name == "Workspace")
        #expect(graph.projects.count == 1)
        #expect(graph.packages.isEmpty == true)
        #expect(graph.dependencies.isEmpty == true)
        #expect(graph.dependencyConditions.isEmpty == true)
        // Workspace should wrap the single project
        #expect(graph.workspace.projects.count == 1)
        #expect(graph.workspace.projects.first == projectPath)
        #expect(graph.workspace.name == "Workspace")
    }

    @Test("Maps a project with sanitizable target names")
    func projectWithSanitizableTargetNames() async throws {
        // Given
        let pbxProj = PBXProj()

        let xcodeProj = try await XcodeProj.test(
            projectName: "SingleProject",
            pbxProj: pbxProj
        )

        let projectMapper = MockPBXProjectMapping()
        given(projectMapper)
            .map(
                xcodeProj: .any,
                projectNativeTargets: .any
            )
            .willReturn(
                .test()
            )

        // Add a single target to the project
        try PBXNativeTarget.test(
            name: "App-With-Dash",
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        try xcodeProj.write(path: try #require(xcodeProj.path))
        let mapper = XcodeGraphMapper(
            projectMapper: projectMapper
        )
        // When
        _ = try await mapper.buildGraph(from: .project(xcodeProj))

        // Then
        verify(projectMapper)
            .map(
                xcodeProj: .any,
                projectNativeTargets: .matching(
                    {
                        $0.keys.map { $0 } == [
                            "App_With_Dash",
                        ]
                    }
                )
            )
            .called(1)
    }

    @Test("Maps a project with custom target product names")
    func projectWithCustomTargetProductNames() async throws {
        // Given
        let pbxProj = PBXProj()

        let xcodeProj = try await XcodeProj.test(
            projectName: "SingleProject",
            pbxProj: pbxProj
        )

        let projectMapper = MockPBXProjectMapping()
        given(projectMapper)
            .map(
                xcodeProj: .any,
                projectNativeTargets: .any
            )
            .willReturn(
                .test()
            )

        // Add a single target to the project
        try PBXNativeTarget.test(
            name: "Alamofire-tvOS",
            productName: "Alamofire",
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        try xcodeProj.write(path: try #require(xcodeProj.path))
        let mapper = XcodeGraphMapper(
            projectMapper: projectMapper
        )
        // When
        _ = try await mapper.buildGraph(from: .project(xcodeProj))

        // Then
        verify(projectMapper)
            .map(
                xcodeProj: .any,
                projectNativeTargets: .matching(
                    {
                        $0.keys.map { $0 } == [
                            "Alamofire",
                        ]
                    }
                )
            )
            .called(1)
    }

    @Test("Maps a workspace with multiple projects into a single graph")
    func workspaceGraphMultipleProjects() async throws {
        // Given
        let pbxProjA = PBXProj()
        let pbxProjB = PBXProj()

        let debug: XCBuildConfiguration = .testDebug().add(to: pbxProjA).add(to: pbxProjB)
        let releaseConfig: XCBuildConfiguration = .testRelease().add(to: pbxProjA).add(to: pbxProjB)
        let configurationList: XCConfigurationList = .test(
            buildConfigurations: [debug, releaseConfig]
        )
        .add(to: pbxProjA)
        .add(to: pbxProjB)

        let projectA = try await XcodeProj.test(
            projectName: "ProjectA",
            configurationList: configurationList,
            pbxProj: pbxProjA
        )

        let projectB = try await XcodeProj.test(
            projectName: "ProjectB",
            configurationList: configurationList,
            pbxProj: pbxProjB
        )

        let sourceFile = try PBXFileReference.test(
            path: "ViewController.swift",
            lastKnownFileType: "sourcecode.swift"
        ).add(to: pbxProjA).addToMainGroup(in: pbxProjA)

        let buildFile = PBXBuildFile(file: sourceFile).add(to: pbxProjB).add(to: pbxProjA)
        let sourcesPhase = PBXSourcesBuildPhase(files: [buildFile]).add(to: pbxProjB).add(to: pbxProjA)

        // Add targets to each project
        try PBXNativeTarget.test(
            name: "ATarget",
            buildConfigurationList: configurationList,
            buildPhases: [sourcesPhase],
            productType: .framework
        )
        .add(to: pbxProjA)
        .add(to: pbxProjA.rootObject)

        try PBXNativeTarget.test(
            name: "BTarget",
            buildConfigurationList: configurationList,
            buildPhases: [sourcesPhase],
            productType: .framework
        )
        .add(to: pbxProjB)
        .add(to: pbxProjB.rootObject)

        let projectAPath = try #require(projectA.path?.string)
        let projectBPath = try #require(projectB.path?.string)

        let xcworkspace = XCWorkspace(
            data: XCWorkspaceData(
                children: [
                    .file(.init(location: .absolute(projectAPath))),
                    .file(.init(location: .absolute(projectBPath))),
                ]
            ),
            path: .init(projectAPath.appending("/Workspace.xcworkspace"))
        )

        try projectA.write(path: try #require(projectA.path))
        try projectB.write(path: try #require(projectB.path))
        let mapper = XcodeGraphMapper()

        // When
        let graph = try await mapper.buildGraph(from: .workspace(xcworkspace))

        // Then
        #expect(graph.workspace.name == "Workspace")
        #expect(graph.workspace.projects.contains(projectA.projectPath) == true)
        #expect(graph.workspace.projects.contains(projectB.projectPath) == true)
        #expect(graph.projects.count == 2)

        let mappedProjectA = try #require(graph.projects[projectA.projectPath.parentDirectory])
        let mappedProjectB = try #require(graph.projects[projectB.projectPath.parentDirectory])
        #expect(mappedProjectA.targets["ATarget"] != nil)
        #expect(mappedProjectB.targets["BTarget"] != nil)

        // No packages or dependencies
        #expect(graph.packages.isEmpty == true)
        #expect(graph.dependencies.isEmpty == true)
        #expect(graph.dependencyConditions.isEmpty == true)
    }

    @Test("Maps a workspace with multiple projects in different directories into a single graph")
    func workspaceGraphMultipleProjectsInDifferentDirectories() async throws {
        // Given
        //
        // A project structure like this:
        // .
        // ├── Workspace.xcworkspace
        // ├── App
        // │   └── ProjectA.xcodeproj
        // └── Modules
        //     └── ProjectB.xcodeproj
        //

        let pbxProjA = PBXProj()
        let pbxProjB = PBXProj()

        let debug: XCBuildConfiguration = .testDebug().add(to: pbxProjA).add(to: pbxProjB)
        let releaseConfig: XCBuildConfiguration = .testRelease().add(to: pbxProjA).add(to: pbxProjB)
        let configurationList: XCConfigurationList = .test(
            buildConfigurations: [debug, releaseConfig]
        )
        .add(to: pbxProjA)
        .add(to: pbxProjB)

        let projectA = try await XcodeProj.test(
            projectName: "ProjectA",
            configurationList: configurationList,
            pbxProj: pbxProjA,
            path: "/tmp/App/ProjectA.xcodeproj"
        )

        let projectB = try await XcodeProj.test(
            projectName: "ProjectB",
            configurationList: configurationList,
            pbxProj: pbxProjB,
            path: "/tmp/Modules/ProjectB/ProjectB.xcodeproj"
        )

        let projectAPath = try #require(projectA.path?.string)
        let projectBPath = try #require(projectB.path?.string)

        let xcworkspace = XCWorkspace(
            data: XCWorkspaceData(
                children: [
                    .group(.init(location: .group("App"), name: "App", children: [
                        .file(.init(location: .absolute(projectAPath))),
                    ])),
                    .group(.init(location: .group("Modules"), name: "Modules", children: [
                        .file(.init(location: .absolute(projectBPath))),
                    ])),
                ]
            ),
            path: .init("/tmp/Workspace.xcworkspace")
        )

        try projectA.write(path: try #require(projectA.path))
        try projectB.write(path: try #require(projectB.path))
        let mapper = XcodeGraphMapper()

        // When
        let graph = try await mapper.buildGraph(from: .workspace(xcworkspace))

        // Then

        // General workspace checks
        #expect(graph.workspace.name == "Workspace")
        #expect(graph.workspace.projects.contains(projectA.projectPath) == true)
        #expect(graph.workspace.projects.contains(projectB.projectPath) == true)
        #expect(graph.projects.count == 2)

        // Nested paths are correct
        #expect(graph.projects["/tmp/App"] != nil)
        #expect(graph.projects["/tmp/Modules/ProjectB"] != nil)
    }

    @Test("Maps a project graph with dependencies between targets")
    func graphWithDependencies() async throws {
        // Given
        let pbxProj = PBXProj()
        let debug: XCBuildConfiguration = .testDebug().add(to: pbxProj)
        let releaseConfig: XCBuildConfiguration = .testRelease().add(to: pbxProj)
        let configurationList: XCConfigurationList = .test(
            buildConfigurations: [debug, releaseConfig]
        )
        .add(to: pbxProj)

        let xcodeProj = try await XcodeProj.test(
            projectName: "ProjectWithDeps",
            configurationList: configurationList,
            pbxProj: pbxProj
        )

        let sourceFile = try PBXFileReference.test(
            path: "ViewController.swift",
            lastKnownFileType: "sourcecode.swift"
        )
        .add(to: pbxProj)
        .addToMainGroup(in: pbxProj)

        let buildFile = PBXBuildFile(file: sourceFile).add(to: pbxProj)
        let sourcesPhase = PBXSourcesBuildPhase(files: [buildFile]).add(to: pbxProj)

        let appTarget = try PBXNativeTarget.test(
            name: "App",
            buildConfigurationList: configurationList,
            buildPhases: [sourcesPhase],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        // App -> AFramework dependency
        let frameworkTarget = try PBXNativeTarget.test(
            name: "AFramework",
            buildConfigurationList: configurationList,
            buildPhases: [sourcesPhase],
            productType: .framework
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        let dep = PBXTargetDependency(
            name: "AFramework",
            target: frameworkTarget
        )
        .add(to: pbxProj)
        appTarget.dependencies.append(dep)
        try xcodeProj.write(path: try #require(xcodeProj.path))
        let mapper = XcodeGraphMapper()

        // When
        let graph = try await mapper.buildGraph(from: .project(xcodeProj))

        // Then
        // Verify dependencies are mapped
        let targetDep = GraphDependency.target(name: "AFramework", path: xcodeProj.srcPath)
        let expectedDependency = try #require(graph.dependencies.first?.value)

        #expect(expectedDependency == [targetDep])
    }

    @Test("Maps a project graph with local packages")
    func graphWithLocalPackages() async throws {
        // Given
        let pbxProj = PBXProj()
        let debug: XCBuildConfiguration = .testDebug().add(to: pbxProj)
        let releaseConfig: XCBuildConfiguration = .testRelease().add(to: pbxProj)
        let configurationList: XCConfigurationList = .test(
            buildConfigurations: [debug, releaseConfig]
        )
        .add(to: pbxProj)

        let xcodeProj = try await XcodeProj.test(
            projectName: "ProjectWithPackages",
            configurationList: configurationList,
            pbxProj: pbxProj
        )

        try PBXNativeTarget.test(
            name: "App",
            buildConfigurationList: configurationList,
            buildPhases: [],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        try xcodeProj.write(path: try #require(xcodeProj.path))
        let packageMapper = MockPackageMapping()
        let packageInfoLoader = MockPackageInfoLoading()
        let projectMapper = MockPBXProjectMapping()
        given(projectMapper)
            .map(
                xcodeProj: .any,
                projectNativeTargets: .any
            )
            .willReturn(
                .test(
                    packages: [
                        .local(path: "/tmp/LibraryA"),
                        .local(path: "/tmp/LibraryB"),
                    ]
                )
            )
        given(packageInfoLoader)
            .loadPackageInfo(at: .value("/tmp/LibraryA"))
            .willReturn(
                .test(
                    name: "LibraryA"
                )
            )
        given(packageInfoLoader)
            .loadPackageInfo(at: .value("/tmp/LibraryB"))
            .willReturn(
                .test(
                    name: "LibraryB"
                )
            )
        let libraryAProject: Project = .test(
            targets: [
                .test(
                    name: "LibraryA",
                    dependencies: [
                        .project(
                            target: "LibraryB",
                            path: "/tmp/LibraryB",
                            status: .required,
                            condition: nil
                        ),
                    ]
                ),
                .test(
                    name: "LibraryATests",
                    dependencies: [
                        .target(
                            name: "LibraryA",
                            status: .required,
                            condition: nil
                        ),
                    ]
                ),
            ]
        )
        let libraryBProject: Project = .test(
            targets: [
                .test(
                    name: "LibraryB"
                ),
            ]
        )
        given(packageMapper)
            .map(
                .any,
                packages: .any,
                at: .value("/tmp/LibraryA")
            )
            .willReturn(libraryAProject)
        given(packageMapper)
            .map(
                .any,
                packages: .any,
                at: .value("/tmp/LibraryB")
            )
            .willReturn(libraryBProject)
        let mapper = XcodeGraphMapper(
            packageInfoLoader: packageInfoLoader,
            packageMapper: packageMapper,
            projectMapper: projectMapper
        )

        // When
        let graph = try await mapper.buildGraph(from: .project(xcodeProj))

        // Then
        #expect(graph.projects["/tmp/LibraryA"] == libraryAProject)
        #expect(graph.projects["/tmp/LibraryB"] == libraryBProject)
        #expect(
            graph.dependencies == [
                .target(
                    name: "LibraryATests",
                    path: "/tmp/LibraryA",
                    status: .required
                ): [
                    .target(
                        name: "LibraryA",
                        path: "/tmp/LibraryA",
                        status: .required
                    ),
                ],
                .target(
                    name: "LibraryA",
                    path: "/tmp/LibraryA",
                    status: .required
                ): [
                    .target(
                        name: "LibraryB",
                        path: "/tmp/LibraryB",
                        status: .required
                    ),
                ],
            ]
        )
    }
}
