import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistLoader
import TuistSupport
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
        XCTAssertEqual(ProjectEditorError.noEditableFiles(AbsolutePath.root).description, "There are no editable files at \(AbsolutePath.root.pathString)")
    }
}

final class ProjectEditorTests: TuistUnitTestCase {
    var generator: MockDescriptorGenerator!
    var projectEditorMapper: MockProjectEditorMapper!
    var resourceLocator: MockResourceLocator!
    var manifestFilesLocator: MockManifestFilesLocator!
    var helpersDirectoryLocator: MockHelpersDirectoryLocator!
    var writer: MockXcodeProjWriter!
    var templatesDirectoryLocator: MockTemplatesDirectoryLocator!
    var subject: ProjectEditor!

    override func setUp() {
        super.setUp()
        generator = MockDescriptorGenerator()
        projectEditorMapper = MockProjectEditorMapper()
        resourceLocator = MockResourceLocator()
        manifestFilesLocator = MockManifestFilesLocator()
        helpersDirectoryLocator = MockHelpersDirectoryLocator()
        writer = MockXcodeProjWriter()
        templatesDirectoryLocator = MockTemplatesDirectoryLocator()
        subject = ProjectEditor(generator: generator,
                                projectEditorMapper: projectEditorMapper,
                                resourceLocator: resourceLocator,
                                manifestFilesLocator: manifestFilesLocator,
                                helpersDirectoryLocator: helpersDirectoryLocator,
                                writer: writer,
                                templatesDirectoryLocator: templatesDirectoryLocator)
    }

    override func tearDown() {
        super.tearDown()
        generator = nil
        projectEditorMapper = nil
        resourceLocator = nil
        manifestFilesLocator = nil
        helpersDirectoryLocator = nil
        templatesDirectoryLocator = nil
        subject = nil
    }

    func test_edit() throws {
        // Given
        let directory = try temporaryPath()
        let projectDescriptionPath = directory.appending(component: "ProjectDescription.framework")
        let graph = ValueGraph.test(name: "Edit")
        let helpersDirectory = directory.appending(component: "ProjectDescriptionHelpers")
        try FileHandler.shared.createFolder(helpersDirectory)
        let helpers = ["A.swift", "B.swift"].map { helpersDirectory.appending(component: $0) }
        try helpers.forEach { try FileHandler.shared.touch($0) }
        let manifests: [(Manifest, AbsolutePath)] = [(.project, directory.appending(component: "Project.swift"))]
        let tuistPath = AbsolutePath(ProcessInfo.processInfo.arguments.first!)
        let setupPath = directory.appending(components: "Setup.swift")
        let configPath = directory.appending(components: "Tuist", "Config.swift")
        let dependenciesPath = directory.appending(components: "Tuist", "Dependencies.swif")

        resourceLocator.projectDescriptionStub = { projectDescriptionPath }
        manifestFilesLocator.locateProjectManifestsStub = manifests
        manifestFilesLocator.locateConfigStub = configPath
        manifestFilesLocator.locateDependenciesStub = dependenciesPath
        manifestFilesLocator.locateSetupStub = setupPath
        helpersDirectoryLocator.locateStub = helpersDirectory
        projectEditorMapper.mapStub = graph
        generator.generateWorkspaceStub = { _ in
            .test(xcworkspacePath: directory.appending(component: "Edit.xcworkspacepath"))
        }

        // When
        try _ = subject.edit(at: directory, in: directory)

        // Then
        XCTAssertEqual(projectEditorMapper.mapArgs.count, 1)
        let mapArgs = projectEditorMapper.mapArgs.first
        XCTAssertEqual(mapArgs?.tuistPath, tuistPath)
        XCTAssertEqual(mapArgs?.helpers, helpers)
        XCTAssertEqual(mapArgs?.sourceRootPath, directory)
        XCTAssertEqual(mapArgs?.projectDescriptionPath, projectDescriptionPath)
        XCTAssertEqual(mapArgs?.configPath, configPath)
        XCTAssertEqual(mapArgs?.setupPath, setupPath)
        XCTAssertEqual(mapArgs?.dependenciesPath, dependenciesPath)
    }

    func test_edit_when_there_are_no_editable_files() throws {
        // Given
        let directory = try temporaryPath()
        let projectDescriptionPath = directory.appending(component: "ProjectDescription.framework")
        let graph = ValueGraph.test(name: "Edit")
        let helpersDirectory = directory.appending(component: "ProjectDescriptionHelpers")
        try FileHandler.shared.createFolder(helpersDirectory)

        resourceLocator.projectDescriptionStub = { projectDescriptionPath }
        manifestFilesLocator.locateProjectManifestsStub = []
        manifestFilesLocator.locatePluginManifestsStub = []
        helpersDirectoryLocator.locateStub = helpersDirectory
        projectEditorMapper.mapStub = graph
        generator.generateWorkspaceStub = { _ in
            .test(xcworkspacePath: directory.appending(component: "Edit.xcworkspacepath"))
        }

        // Then
        XCTAssertThrowsSpecific(
            // When
            try subject.edit(at: directory, in: directory), ProjectEditorError.noEditableFiles(directory)
        )
    }

    func test_edit_with_plugin() throws {
        // Given
        let directory = try temporaryPath()
        let projectDescriptionPath = directory.appending(component: "ProjectDescription.framework")
        let graph = ValueGraph.test(name: "Edit")
        let pluginManifest = directory.appending(component: "Plugin.swift")
        let tuistPath = AbsolutePath(ProcessInfo.processInfo.arguments.first!)

        // When
        resourceLocator.projectDescriptionStub = { projectDescriptionPath }
        manifestFilesLocator.locatePluginManifestsStub = [pluginManifest]

        projectEditorMapper.mapStub = graph
        generator.generateWorkspaceStub = { _ in
            .test(xcworkspacePath: directory.appending(component: "Edit.xcworkspace"))
        }

        // When
        try _ = subject.edit(at: directory, in: directory)

        // Then
        XCTAssertEqual(projectEditorMapper.mapArgs.count, 1)
        let mapArgs = projectEditorMapper.mapArgs.first
        XCTAssertEqual(mapArgs?.tuistPath, tuistPath)
        XCTAssertEqual(mapArgs?.sourceRootPath, directory)
        XCTAssertEqual(mapArgs?.projectDescriptionPath, projectDescriptionPath)
        XCTAssertEqual(mapArgs?.pluginManifests, [pluginManifest])
    }

    func test_edit_with_many_plugins() throws {
        // Given
        let directory = try temporaryPath()
        let projectDescriptionPath = directory.appending(component: "ProjectDescription.framework")
        let graph = ValueGraph.test(name: "Edit")
        let pluginManifests = [
            directory.appending(components: "A", "Plugin.swift"),
            directory.appending(components: "B", "Plugin.swift"),
            directory.appending(components: "C", "Plugin.swift"),
            directory.appending(components: "D", "Plugin.swift"),
        ]
        let tuistPath = AbsolutePath(ProcessInfo.processInfo.arguments.first!)

        // When
        resourceLocator.projectDescriptionStub = { projectDescriptionPath }
        manifestFilesLocator.locatePluginManifestsStub = pluginManifests

        projectEditorMapper.mapStub = graph
        generator.generateWorkspaceStub = { _ in
            .test(xcworkspacePath: directory.appending(component: "Edit.xcworkspacepath"))
        }

        // When
        try _ = subject.edit(at: directory, in: directory)

        // Then
        XCTAssertEqual(projectEditorMapper.mapArgs.count, 1)
        let mapArgs = projectEditorMapper.mapArgs.first
        XCTAssertEqual(mapArgs?.tuistPath, tuistPath)
        XCTAssertEqual(mapArgs?.sourceRootPath, directory)
        XCTAssertEqual(mapArgs?.projectDescriptionPath, projectDescriptionPath)
        XCTAssertEqual(mapArgs?.pluginManifests, pluginManifests)
    }
}
