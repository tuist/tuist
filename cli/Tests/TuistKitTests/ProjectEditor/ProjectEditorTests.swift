import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistGenerator
import TuistLoader
import TuistPlugin
import TuistScaffold
import TuistSupport
import XcodeGraph
@testable import TuistKit
@testable import TuistTesting

@Suite(.withMockedDependencies()) struct ProjectEditorErrorTests {
    @Test func test_type() {
        #expect(ProjectEditorError.noEditableFiles(AbsolutePath.root).type == .abort)
    }

    @Test func test_description() {
        #expect(
            ProjectEditorError.noEditableFiles(AbsolutePath.root).description ==
                "There are no editable files at \(AbsolutePath.root.pathString)"
        )
    }
}

@Suite(.withMockedDependencies()) struct ProjectEditorTests {
    private let fileSystem = FileSystem()
    private var generator: MockDescriptorGenerator!
    private var projectEditorMapper: MockProjectEditorMapper!
    private var resourceLocator: MockResourceLocator!
    private var manifestFilesLocator: MockManifestFilesLocating!
    private var helpersDirectoryLocator: MockHelpersDirectoryLocator!
    private var writer: MockXcodeProjWriter!
    private var templatesDirectoryLocator: MockTemplatesDirectoryLocating!
    private var projectDescriptionHelpersBuilder: MockProjectDescriptionHelpersBuilder!
    private var projectDescriptionHelpersBuilderFactory: MockProjectDescriptionHelpersBuilderFactory!
    private var subject: ProjectEditor!

    init() {
        generator = MockDescriptorGenerator()
        projectEditorMapper = MockProjectEditorMapper()
        resourceLocator = MockResourceLocator()
        manifestFilesLocator = MockManifestFilesLocating()
        helpersDirectoryLocator = MockHelpersDirectoryLocator()
        writer = MockXcodeProjWriter()
        templatesDirectoryLocator = MockTemplatesDirectoryLocating()
        projectDescriptionHelpersBuilder = MockProjectDescriptionHelpersBuilder()
        projectDescriptionHelpersBuilderFactory = MockProjectDescriptionHelpersBuilderFactory()
        let builder = projectDescriptionHelpersBuilder!
        projectDescriptionHelpersBuilderFactory
            .projectDescriptionHelpersBuilderStub = { _ in builder }

        subject = ProjectEditor(
            generator: generator,
            projectEditorMapper: projectEditorMapper,
            resourceLocator: resourceLocator,
            manifestFilesLocator: manifestFilesLocator,
            helpersDirectoryLocator: helpersDirectoryLocator,
            writer: writer,
            templatesDirectoryLocator: templatesDirectoryLocator,
            projectDescriptionHelpersBuilderFactory: projectDescriptionHelpersBuilderFactory
        )
    }

    @Test(.inTemporaryDirectory) func test_edit() async throws {
        // Given
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let projectDescriptionPath = directory.appending(component: "ProjectDescription.framework")
        let graph = Graph.test(name: "Edit")
        let helpersDirectory = directory.appending(component: "ProjectDescriptionHelpers")
        try FileHandler.shared.createFolder(helpersDirectory)
        let helpers = ["A.swift", "B.swift", "Documentation.docc"].map { helpersDirectory.appending(component: $0) }
        try helpers.forEach { try FileHandler.shared.touch($0) }
        let manifests = [
            ManifestFilesLocator.ProjectManifest(
                manifest: .project,
                path: directory.appending(component: "Project.swift")
            ),
        ]
        let tuistPath = try AbsolutePath(validating: Environment.current.arguments.first!)
        let configPath = directory.appending(components: Constants.tuistManifestFileName)
        let packageManifestPath = directory.appending(components: "Tuist", "Package.swift")
        try FileHandler.shared.createFolder(directory.appending(component: "a folder"))
        try FileHandler.shared.write(
            """
            a folder
            B.swift
            """,
            path: directory.appending(component: ".tuistignore"),
            atomically: true
        )

        resourceLocator.projectDescriptionStub = { projectDescriptionPath }
        given(manifestFilesLocator).locateProjectManifests(
            at: .any,
            excluding: .value(
                [
                    "**/.build/**",
                    "\(directory.pathString)/a folder/**",
                    "\(directory.pathString)/B.swift",
                ]
            ),
            onlyCurrentDirectory: .any
        )
        .willReturn(manifests)
        given(manifestFilesLocator).locateConfig(at: .any).willReturn(configPath)
        given(manifestFilesLocator).locatePackageManifest(at: .any).willReturn(packageManifestPath)
        given(manifestFilesLocator)
            .locatePluginManifests(at: .any, excluding: .any, onlyCurrentDirectory: .any)
            .willReturn([])
        helpersDirectoryLocator.locateStub = helpersDirectory
        projectEditorMapper.mapStub = graph
        generator.generateWorkspaceStub = { _ in
            .test(xcworkspacePath: directory.appending(component: "Edit.xcworkspacepath"))
        }
        given(templatesDirectoryLocator)
            .locateUserTemplates(at: .any)
            .willReturn(nil)

        // When
        try _ = await subject.edit(at: directory, in: directory, onlyCurrentDirectory: false, plugins: .test())

        // Then
        #expect(projectEditorMapper.mapArgs.count == 1)
        let mapArgs = projectEditorMapper.mapArgs.first
        #expect(mapArgs?.tuistPath == tuistPath)
        #expect(mapArgs?.helpers == helpers)
        #expect(mapArgs?.sourceRootPath == directory)
        #expect(mapArgs?.projectDescriptionPath == projectDescriptionPath.parentDirectory)
        #expect(mapArgs?.configPath == configPath)
        #expect(mapArgs?.packageManifestPath == packageManifestPath)
    }

    @Test(.inTemporaryDirectory) func edit_when_there_are_no_editable_files() async throws {
        // Given
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let projectDescriptionPath = directory.appending(component: "ProjectDescription.framework")
        let graph = Graph.test(name: "Edit")
        let helpersDirectory = directory.appending(component: "ProjectDescriptionHelpers")
        try FileHandler.shared.createFolder(helpersDirectory)

        resourceLocator.projectDescriptionStub = { projectDescriptionPath }
        given(manifestFilesLocator)
            .locateProjectManifests(at: .any, excluding: .any, onlyCurrentDirectory: .any)
            .willReturn([])
        given(manifestFilesLocator)
            .locatePluginManifests(at: .any, excluding: .any, onlyCurrentDirectory: .any)
            .willReturn([])
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(nil)
        given(manifestFilesLocator)
            .locateConfig(at: .any)
            .willReturn(nil)
        helpersDirectoryLocator.locateStub = helpersDirectory
        projectEditorMapper.mapStub = graph
        generator.generateWorkspaceStub = { _ in
            .test(xcworkspacePath: directory.appending(component: "Edit.xcworkspacepath"))
        }
        given(templatesDirectoryLocator)
            .locateUserTemplates(at: .any)
            .willReturn(nil)

        // Then
        // When / Then
        await #expect(throws: ProjectEditorError.noEditableFiles(directory)) {
            try await subject.edit(at: directory, in: directory, onlyCurrentDirectory: false, plugins: .test())
        }
    }

    @Test(.inTemporaryDirectory) func edit_with_plugin() async throws {
        // Given
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let projectDescriptionPath = directory.appending(component: "ProjectDescription.framework")
        let graph = Graph.test(name: "Edit")
        let pluginManifest = directory.appending(component: "Plugin.swift")
        let tuistPath = try AbsolutePath(validating: Environment.current.arguments.first!)

        // When
        resourceLocator.projectDescriptionStub = { projectDescriptionPath }
        given(manifestFilesLocator)
            .locatePluginManifests(at: .any, excluding: .any, onlyCurrentDirectory: .any)
            .willReturn([pluginManifest])
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(nil)
        given(manifestFilesLocator)
            .locateConfig(at: .any)
            .willReturn(nil)
        given(manifestFilesLocator)
            .locateProjectManifests(at: .any, excluding: .any, onlyCurrentDirectory: .any)
            .willReturn([])

        projectEditorMapper.mapStub = graph
        generator.generateWorkspaceStub = { _ in
            .test(xcworkspacePath: directory.appending(component: "Edit.xcworkspace"))
        }
        given(templatesDirectoryLocator)
            .locateUserTemplates(at: .any)
            .willReturn(nil)

        // When
        try _ = await subject.edit(at: directory, in: directory, onlyCurrentDirectory: false, plugins: .test())

        // Then
        #expect(projectEditorMapper.mapArgs.count == 1)
        let mapArgs = projectEditorMapper.mapArgs.first
        #expect(mapArgs?.tuistPath == tuistPath)
        #expect(mapArgs?.sourceRootPath == directory)
        #expect(mapArgs?.projectDescriptionPath == projectDescriptionPath.parentDirectory)
        #expect(mapArgs?.editablePluginManifests.map(\.path.basename) == [pluginManifest].map(\.parentDirectory.basename))
        #expect(mapArgs?.pluginProjectDescriptionHelpersModule == [])
    }

    @Test(.inTemporaryDirectory) func edit_with_many_plugins() async throws {
        // Given
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let projectDescriptionPath = directory.appending(component: "ProjectDescription.framework")
        let graph = Graph.test(name: "Edit")
        let pluginManifests = [
            directory.appending(components: "A", "Plugin.swift"),
            directory.appending(components: "B", "Plugin.swift"),
            directory.appending(components: "C", "Plugin.swift"),
            directory.appending(components: "D", "Plugin.swift"),
        ]
        for pluginManifest in pluginManifests {
            try await fileSystem.makeDirectory(at: pluginManifest.parentDirectory)
            try await fileSystem.touch(pluginManifest)
        }
        let tuistPath = try AbsolutePath(validating: Environment.current.arguments.first!)

        // When
        resourceLocator.projectDescriptionStub = { projectDescriptionPath }
        given(manifestFilesLocator)
            .locatePluginManifests(at: .any, excluding: .any, onlyCurrentDirectory: .any)
            .willReturn(pluginManifests)
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(nil)
        given(manifestFilesLocator)
            .locateConfig(at: .any)
            .willReturn(nil)
        given(manifestFilesLocator)
            .locateProjectManifests(at: .any, excluding: .any, onlyCurrentDirectory: .any)
            .willReturn([])
        given(templatesDirectoryLocator)
            .locateUserTemplates(at: .any)
            .willReturn(nil)

        projectEditorMapper.mapStub = graph
        generator.generateWorkspaceStub = { _ in
            .test(xcworkspacePath: directory.appending(component: "Edit.xcworkspacepath"))
        }

        // When
        try _ = await subject.edit(at: directory, in: directory, onlyCurrentDirectory: false, plugins: .test())

        // Then
        #expect(projectEditorMapper.mapArgs.count == 1)
        let mapArgs = projectEditorMapper.mapArgs.first
        #expect(mapArgs?.tuistPath == tuistPath)
        #expect(mapArgs?.sourceRootPath == directory)
        #expect(mapArgs?.projectDescriptionPath == projectDescriptionPath.parentDirectory)
        #expect(mapArgs?.editablePluginManifests.map(\.path).sorted() == pluginManifests.map(\.parentDirectory))
        #expect(mapArgs?.pluginProjectDescriptionHelpersModule == [])
    }

    @Test(.inTemporaryDirectory) func edit_project_with_local_plugins() async throws {
        // Given
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let projectDescriptionPath = directory.appending(component: "ProjectDescription.framework")
        let graph = Graph.test(name: "Edit")

        // Project
        let manifests = [
            ManifestFilesLocator.ProjectManifest(
                manifest: .project,
                path: directory.appending(component: "Project.swift")
            ),
        ]

        // Local plugin
        let pluginDirectory = directory.appending(component: "LocalPlugin")
        let pluginHelpersDirectory = pluginDirectory.appending(component: "ProjectDescriptionHelpers")
        try FileHandler.shared.createFolder(pluginDirectory)
        try FileHandler.shared.createFolder(pluginHelpersDirectory)
        let pluginManifestPath = pluginDirectory.appending(component: "Plugin.swift")
        try FileHandler.shared.touch(pluginManifestPath)

        let tuistPath = try AbsolutePath(validating: Environment.current.arguments.first!)

        resourceLocator.projectDescriptionStub = { projectDescriptionPath }
        given(manifestFilesLocator)
            .locateProjectManifests(at: .any, excluding: .any, onlyCurrentDirectory: .any)
            .willReturn(manifests)
        given(manifestFilesLocator)
            .locatePluginManifests(at: .any, excluding: .any, onlyCurrentDirectory: .any)
            .willReturn([pluginManifestPath])
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(nil)
        given(manifestFilesLocator)
            .locateConfig(at: .any)
            .willReturn(nil)
        projectEditorMapper.mapStub = graph
        generator.generateWorkspaceStub = { _ in
            .test(xcworkspacePath: directory.appending(component: "Edit.xcworkspacepath"))
        }
        given(templatesDirectoryLocator)
            .locateUserTemplates(at: .any)
            .willReturn(nil)

        // When
        let plugins = Plugins.test(projectDescriptionHelpers: [
            .init(name: "LocalPlugin", path: pluginManifestPath, location: .local),
        ])
        try _ = await subject.edit(at: directory, in: directory, onlyCurrentDirectory: false, plugins: plugins)

        // Then
        #expect(projectEditorMapper.mapArgs.count == 1)
        let mapArgs = projectEditorMapper.mapArgs.first
        #expect(mapArgs?.tuistPath == tuistPath)
        #expect(mapArgs?.sourceRootPath == directory)
        #expect(mapArgs?.projectDescriptionPath == projectDescriptionPath.parentDirectory)
        #expect(mapArgs?.editablePluginManifests.map(\.name) == ["LocalPlugin"])
        #expect(
            mapArgs?.editablePluginManifests.map(\.path.basename) ==
                [pluginManifestPath].map(\.parentDirectory.basename)
        )
        #expect(mapArgs?.pluginProjectDescriptionHelpersModule == [])
    }

    @Test(.inTemporaryDirectory) func edit_project_with_local_plugin_outside_editing_path() async throws {
        // Given
        let rootPath = try #require(FileSystem.temporaryTestDirectory)
        let editingPath = rootPath.appending(component: "Editing")
        let projectDescriptionPath = editingPath.appending(component: "ProjectDescription.framework")
        let graph = Graph.test(name: "Edit")

        // Project
        let manifests = [
            ManifestFilesLocator.ProjectManifest(
                manifest: .project,
                path: editingPath.appending(component: "Project.swift")
            ),
        ]

        // Local plugin
        let pluginManifestPath = rootPath.appending(component: "Plugin.swift")

        let tuistPath = try AbsolutePath(validating: Environment.current.arguments.first!)

        resourceLocator.projectDescriptionStub = { projectDescriptionPath }
        given(manifestFilesLocator)
            .locateProjectManifests(at: .any, excluding: .any, onlyCurrentDirectory: .any)
            .willReturn(manifests)
        given(manifestFilesLocator)
            .locatePluginManifests(at: .any, excluding: .any, onlyCurrentDirectory: .any)
            .willReturn([pluginManifestPath])
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(nil)
        given(manifestFilesLocator)
            .locateConfig(at: .any)
            .willReturn(nil)
        projectEditorMapper.mapStub = graph
        generator.generateWorkspaceStub = { _ in
            .test(xcworkspacePath: editingPath.appending(component: "Edit.xcworkspacepath"))
        }
        given(templatesDirectoryLocator)
            .locateUserTemplates(at: .any)
            .willReturn(nil)

        // When
        let plugins = Plugins.test(projectDescriptionHelpers: [
            .init(name: "LocalPlugin", path: pluginManifestPath, location: .local),
        ])

        try _ = await subject.edit(at: editingPath, in: editingPath, onlyCurrentDirectory: false, plugins: plugins)

        // Then
        #expect(projectEditorMapper.mapArgs.count == 1)
        let mapArgs = projectEditorMapper.mapArgs.first
        #expect(mapArgs?.tuistPath == tuistPath)
        #expect(mapArgs?.sourceRootPath == editingPath)
        #expect(mapArgs?.projectDescriptionPath == projectDescriptionPath.parentDirectory)
        #expect(mapArgs?.editablePluginManifests.map(\.name) == ["LocalPlugin"])
        #expect(
            mapArgs?.editablePluginManifests.map(\.path.basename) ==
                [pluginManifestPath].map(\.parentDirectory.basename)
        )
        #expect(mapArgs?.pluginProjectDescriptionHelpersModule == [])
    }

    @Test(.inTemporaryDirectory) func edit_project_deduplicates_plugins_with_same_directory_name() async throws {
        // Given
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let projectDescriptionPath = directory.appending(component: "ProjectDescription.framework")
        let graph = Graph.test(name: "Edit")

        let manifests = [
            ManifestFilesLocator.ProjectManifest(
                manifest: .project,
                path: directory.appending(component: "Project.swift")
            ),
        ]

        // Multiple Plugin.swift files discovered by filesystem scan sharing the same directory name
        let discoveredPluginPath1 = directory.appending(components: "examples", "app1", "LocalPlugin", "Plugin.swift")
        let discoveredPluginPath2 = directory.appending(components: "examples", "app2", "LocalPlugin", "Plugin.swift")
        let discoveredPluginPath3 = directory.appending(components: "fixtures", "LocalPlugin", "Plugin.swift")

        let tuistPath = try AbsolutePath(validating: Environment.current.arguments.first!)

        resourceLocator.projectDescriptionStub = { projectDescriptionPath }
        given(manifestFilesLocator)
            .locateProjectManifests(at: .any, excluding: .any, onlyCurrentDirectory: .any)
            .willReturn(manifests)
        given(manifestFilesLocator)
            .locatePluginManifests(at: .any, excluding: .any, onlyCurrentDirectory: .any)
            .willReturn([discoveredPluginPath1, discoveredPluginPath2, discoveredPluginPath3])
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(nil)
        given(manifestFilesLocator)
            .locateConfig(at: .any)
            .willReturn(nil)
        projectEditorMapper.mapStub = graph
        generator.generateWorkspaceStub = { _ in
            .test(xcworkspacePath: directory.appending(component: "Edit.xcworkspacepath"))
        }
        given(templatesDirectoryLocator)
            .locateUserTemplates(at: .any)
            .willReturn(nil)

        // When
        try _ = await subject.edit(at: directory, in: directory, onlyCurrentDirectory: false, plugins: .none)

        // Then
        #expect(projectEditorMapper.mapArgs.count == 1)
        let mapArgs = projectEditorMapper.mapArgs.first
        let pluginNames = try #require(mapArgs?.editablePluginManifests.map(\.name).sorted())
        #expect(pluginNames.count == 3)
        #expect(pluginNames.contains("LocalPlugin"))
        let renamedNames = pluginNames.filter { $0 != "LocalPlugin" }
        for name in renamedNames {
            #expect(name.hasSuffix("-LocalPlugin"), "Expected parent directory prefix, got: \(name)")
        }
    }

    @Test(.inTemporaryDirectory) func edit_project_with_remote_plugin() async throws {
        // Given
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let projectDescriptionPath = directory.appending(component: "ProjectDescription.framework")
        let graph = Graph.test(name: "Edit")

        // Project
        let manifests = [
            ManifestFilesLocator.ProjectManifest(
                manifest: .project,
                path: directory.appending(component: "Project.swift")
            ),
        ]
        let tuistPath = try AbsolutePath(validating: Environment.current.arguments.first!)

        resourceLocator.projectDescriptionStub = { projectDescriptionPath }
        given(manifestFilesLocator)
            .locateProjectManifests(at: .any, excluding: .any, onlyCurrentDirectory: .any)
            .willReturn(manifests)
        given(manifestFilesLocator)
            .locatePluginManifests(at: .any, excluding: .any, onlyCurrentDirectory: .any)
            .willReturn([])
        given(manifestFilesLocator)
            .locatePackageManifest(at: .any)
            .willReturn(nil)
        given(manifestFilesLocator)
            .locateConfig(at: .any)
            .willReturn(nil)
        projectEditorMapper.mapStub = graph
        generator.generateWorkspaceStub = { _ in
            .test(xcworkspacePath: directory.appending(component: "Edit.xcworkspacepath"))
        }
        given(templatesDirectoryLocator)
            .locateUserTemplates(at: .any)
            .willReturn(nil)

        projectDescriptionHelpersBuilder.buildPluginsStub = { _, _, plugins in
            plugins.map { ProjectDescriptionHelpersModule(name: $0.name, path: $0.path) }
        }

        // When
        let plugins = Plugins.test(projectDescriptionHelpers: [
            .init(name: "RemotePlugin", path: try AbsolutePath(validating: "/Some/Path/To/Plugin"), location: .remote),
        ])
        try _ = await subject.edit(at: directory, in: directory, onlyCurrentDirectory: false, plugins: plugins)

        // Then
        #expect(projectEditorMapper.mapArgs.count == 1)
        let mapArgs = projectEditorMapper.mapArgs.first
        #expect(mapArgs?.tuistPath == tuistPath)
        #expect(mapArgs?.sourceRootPath == directory)
        #expect(mapArgs?.projectDescriptionPath == projectDescriptionPath.parentDirectory)
        #expect(try #require(mapArgs?.editablePluginManifests.isEmpty))
        #expect(
            mapArgs?.pluginProjectDescriptionHelpersModule ==
                [ProjectDescriptionHelpersModule(
                    name: "RemotePlugin",
                    path: try AbsolutePath(validating: "/Some/Path/To/Plugin")
                )]
        )
    }
}
