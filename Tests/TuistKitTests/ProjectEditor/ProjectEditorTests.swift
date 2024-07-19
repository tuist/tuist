import Foundation
import MockableTest
import Path
import TuistCore
import TuistLoader
import TuistPlugin
import TuistPluginTesting
import TuistSupport
import XcodeGraph
import XCTest

@testable import TuistCoreTesting
@testable import TuistGeneratorTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistScaffoldTesting
@testable import TuistSupportTesting

final class ProjectEditorErrorTests: TuistUnitTestCase {
    func test_type() {
        XCTAssertEqual(ProjectEditorError.noEditableFiles(AbsolutePath.root).type, .abort)
    }

    func test_description() {
        XCTAssertEqual(
            ProjectEditorError.noEditableFiles(AbsolutePath.root).description,
            "There are no editable files at \(AbsolutePath.root.pathString)"
        )
    }
}

final class ProjectEditorTests: TuistUnitTestCase {
    private var generator: MockDescriptorGenerator!
    private var projectEditorMapper: MockProjectEditorMapper!
    private var resourceLocator: MockResourceLocator!
    private var manifestFilesLocator: MockManifestFilesLocating!
    private var helpersDirectoryLocator: MockHelpersDirectoryLocator!
    private var writer: MockXcodeProjWriter!
    private var templatesDirectoryLocator: MockTemplatesDirectoryLocator!
    private var projectDescriptionHelpersBuilder: MockProjectDescriptionHelpersBuilder!
    private var projectDescriptionHelpersBuilderFactory: MockProjectDescriptionHelpersBuilderFactory!
    private var subject: ProjectEditor!

    override func setUp() {
        super.setUp()
        generator = MockDescriptorGenerator()
        projectEditorMapper = MockProjectEditorMapper()
        resourceLocator = MockResourceLocator()
        manifestFilesLocator = MockManifestFilesLocating()
        helpersDirectoryLocator = MockHelpersDirectoryLocator()
        writer = MockXcodeProjWriter()
        templatesDirectoryLocator = MockTemplatesDirectoryLocator()
        projectDescriptionHelpersBuilder = MockProjectDescriptionHelpersBuilder()
        projectDescriptionHelpersBuilderFactory = MockProjectDescriptionHelpersBuilderFactory()
        projectDescriptionHelpersBuilderFactory
            .projectDescriptionHelpersBuilderStub = { _ in self.projectDescriptionHelpersBuilder }

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

    override func tearDown() {
        generator = nil
        projectEditorMapper = nil
        resourceLocator = nil
        manifestFilesLocator = nil
        helpersDirectoryLocator = nil
        templatesDirectoryLocator = nil
        subject = nil
        super.tearDown()
    }

    func test_edit() async throws {
        // Given
        let directory = try temporaryPath()
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
        let tuistPath = try AbsolutePath(validating: ProcessInfo.processInfo.arguments.first!)
        let configPath = directory.appending(components: "Tuist", "Config.swift")
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

        // When
        try _ = await subject.edit(at: directory, in: directory, onlyCurrentDirectory: false, plugins: .test())

        // Then
        XCTAssertEqual(projectEditorMapper.mapArgs.count, 1)
        let mapArgs = projectEditorMapper.mapArgs.first
        XCTAssertEqual(mapArgs?.tuistPath, tuistPath)
        XCTAssertEqual(mapArgs?.helpers, helpers)
        XCTAssertEqual(mapArgs?.sourceRootPath, directory)
        XCTAssertEqual(mapArgs?.projectDescriptionPath, projectDescriptionPath.parentDirectory)
        XCTAssertEqual(mapArgs?.configPath, configPath)
        XCTAssertEqual(mapArgs?.packageManifestPath, packageManifestPath)
    }

    func test_edit_when_there_are_no_editable_files() async throws {
        // Given
        let directory = try temporaryPath()
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

        // Then
        await XCTAssertThrowsSpecific(
            // When
            try await subject.edit(at: directory, in: directory, onlyCurrentDirectory: false, plugins: .test()),
            ProjectEditorError.noEditableFiles(directory)
        )
    }

    func test_edit_with_plugin() async throws {
        // Given
        let directory = try temporaryPath()
        let projectDescriptionPath = directory.appending(component: "ProjectDescription.framework")
        let graph = Graph.test(name: "Edit")
        let pluginManifest = directory.appending(component: "Plugin.swift")
        let tuistPath = try AbsolutePath(validating: ProcessInfo.processInfo.arguments.first!)

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

        // When
        try _ = await subject.edit(at: directory, in: directory, onlyCurrentDirectory: false, plugins: .test())

        // Then
        XCTAssertEqual(projectEditorMapper.mapArgs.count, 1)
        let mapArgs = projectEditorMapper.mapArgs.first
        XCTAssertEqual(mapArgs?.tuistPath, tuistPath)
        XCTAssertEqual(mapArgs?.sourceRootPath, directory)
        XCTAssertEqual(mapArgs?.projectDescriptionPath, projectDescriptionPath.parentDirectory)
        XCTAssertEqual(mapArgs?.editablePluginManifests.map(\.path), [pluginManifest].map(\.parentDirectory))
        XCTAssertEqual(mapArgs?.pluginProjectDescriptionHelpersModule, [])
    }

    func test_edit_with_many_plugins() async throws {
        // Given
        let directory = try temporaryPath()
        let projectDescriptionPath = directory.appending(component: "ProjectDescription.framework")
        let graph = Graph.test(name: "Edit")
        let pluginManifests = [
            directory.appending(components: "A", "Plugin.swift"),
            directory.appending(components: "B", "Plugin.swift"),
            directory.appending(components: "C", "Plugin.swift"),
            directory.appending(components: "D", "Plugin.swift"),
        ]
        let tuistPath = try AbsolutePath(validating: ProcessInfo.processInfo.arguments.first!)

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

        projectEditorMapper.mapStub = graph
        generator.generateWorkspaceStub = { _ in
            .test(xcworkspacePath: directory.appending(component: "Edit.xcworkspacepath"))
        }

        // When
        try _ = await subject.edit(at: directory, in: directory, onlyCurrentDirectory: false, plugins: .test())

        // Then
        XCTAssertEqual(projectEditorMapper.mapArgs.count, 1)
        let mapArgs = projectEditorMapper.mapArgs.first
        XCTAssertEqual(mapArgs?.tuistPath, tuistPath)
        XCTAssertEqual(mapArgs?.sourceRootPath, directory)
        XCTAssertEqual(mapArgs?.projectDescriptionPath, projectDescriptionPath.parentDirectory)
        XCTAssertEqual(mapArgs?.editablePluginManifests.map(\.path).sorted(), pluginManifests.map(\.parentDirectory))
        XCTAssertEqual(mapArgs?.pluginProjectDescriptionHelpersModule, [])
    }

    func test_edit_project_with_local_plugins() async throws {
        // Given
        let directory = try temporaryPath()
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
        let pluginDirectory = directory.appending(component: "Plugin")
        let pluginHelpersDirectory = pluginDirectory.appending(component: "ProjectDescriptionHelpers")
        try FileHandler.shared.createFolder(pluginDirectory)
        try FileHandler.shared.createFolder(pluginHelpersDirectory)
        let pluginManifestPath = pluginDirectory.appending(component: "Plugin.swift")
        try FileHandler.shared.touch(pluginManifestPath)

        let tuistPath = try AbsolutePath(validating: ProcessInfo.processInfo.arguments.first!)

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

        // When
        let plugins = Plugins.test(projectDescriptionHelpers: [
            .init(name: "LocalPlugin", path: pluginManifestPath, location: .local),
        ])
        try _ = await subject.edit(at: directory, in: directory, onlyCurrentDirectory: false, plugins: plugins)

        // Then
        XCTAssertEqual(projectEditorMapper.mapArgs.count, 1)
        let mapArgs = projectEditorMapper.mapArgs.first
        XCTAssertEqual(mapArgs?.tuistPath, tuistPath)
        XCTAssertEqual(mapArgs?.sourceRootPath, directory)
        XCTAssertEqual(mapArgs?.projectDescriptionPath, projectDescriptionPath.parentDirectory)
        XCTAssertEqual(mapArgs?.editablePluginManifests.map(\.name), ["LocalPlugin"])
        XCTAssertEqual(mapArgs?.editablePluginManifests.map(\.path), [pluginManifestPath].map(\.parentDirectory))
        XCTAssertEqual(mapArgs?.pluginProjectDescriptionHelpersModule, [])
    }

    func test_edit_project_with_local_plugin_outside_editing_path() async throws {
        // Given
        let rootPath = try temporaryPath()
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

        let tuistPath = try AbsolutePath(validating: ProcessInfo.processInfo.arguments.first!)

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

        // When
        let plugins = Plugins.test(projectDescriptionHelpers: [
            .init(name: "LocalPlugin", path: pluginManifestPath, location: .local),
        ])

        try _ = await subject.edit(at: editingPath, in: editingPath, onlyCurrentDirectory: false, plugins: plugins)

        // Then
        XCTAssertEqual(projectEditorMapper.mapArgs.count, 1)
        let mapArgs = projectEditorMapper.mapArgs.first
        XCTAssertEqual(mapArgs?.tuistPath, tuistPath)
        XCTAssertEqual(mapArgs?.sourceRootPath, editingPath)
        XCTAssertEqual(mapArgs?.projectDescriptionPath, projectDescriptionPath.parentDirectory)
        XCTAssertEqual(mapArgs?.editablePluginManifests.map(\.name), ["LocalPlugin"])
        XCTAssertEqual(mapArgs?.editablePluginManifests.map(\.path), [pluginManifestPath].map(\.parentDirectory))
        XCTAssertEqual(mapArgs?.pluginProjectDescriptionHelpersModule, [])
    }

    func test_edit_project_with_remote_plugin() async throws {
        // Given
        let directory = try temporaryPath()
        let projectDescriptionPath = directory.appending(component: "ProjectDescription.framework")
        let graph = Graph.test(name: "Edit")

        // Project
        let manifests = [
            ManifestFilesLocator.ProjectManifest(
                manifest: .project,
                path: directory.appending(component: "Project.swift")
            ),
        ]
        let tuistPath = try AbsolutePath(validating: ProcessInfo.processInfo.arguments.first!)

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

        projectDescriptionHelpersBuilder.buildPluginsStub = { _, _, plugins in
            plugins.map { ProjectDescriptionHelpersModule(name: $0.name, path: $0.path) }
        }

        // When
        let plugins = Plugins.test(projectDescriptionHelpers: [
            .init(name: "RemotePlugin", path: try AbsolutePath(validating: "/Some/Path/To/Plugin"), location: .remote),
        ])
        try _ = await subject.edit(at: directory, in: directory, onlyCurrentDirectory: false, plugins: plugins)

        // Then
        XCTAssertEqual(projectEditorMapper.mapArgs.count, 1)
        let mapArgs = projectEditorMapper.mapArgs.first
        XCTAssertEqual(mapArgs?.tuistPath, tuistPath)
        XCTAssertEqual(mapArgs?.sourceRootPath, directory)
        XCTAssertEqual(mapArgs?.projectDescriptionPath, projectDescriptionPath.parentDirectory)
        XCTAssertEmpty(try XCTUnwrap(mapArgs?.editablePluginManifests))
        XCTAssertEqual(
            mapArgs?.pluginProjectDescriptionHelpersModule,
            [ProjectDescriptionHelpersModule(name: "RemotePlugin", path: try AbsolutePath(validating: "/Some/Path/To/Plugin"))]
        )
    }
}
