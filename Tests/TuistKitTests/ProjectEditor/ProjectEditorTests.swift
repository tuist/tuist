import Foundation
import TSCBasic
import TuistCore
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
    var projectMapper: MockProjectMapper!
    var sideEffectDescriptorExecutor: MockSideEffectDescriptorExecutor!
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
        projectMapper = MockProjectMapper()
        sideEffectDescriptorExecutor = MockSideEffectDescriptorExecutor()
        subject = ProjectEditor(generator: generator,
                                projectEditorMapper: projectEditorMapper,
                                resourceLocator: resourceLocator,
                                manifestFilesLocator: manifestFilesLocator,
                                helpersDirectoryLocator: helpersDirectoryLocator,
                                writer: writer,
                                templatesDirectoryLocator: templatesDirectoryLocator,
                                projectMapper: projectMapper,
                                sideEffectDescriptorExecutor: sideEffectDescriptorExecutor)
    }

    override func tearDown() {
        super.tearDown()
        generator = nil
        projectEditorMapper = nil
        resourceLocator = nil
        manifestFilesLocator = nil
        helpersDirectoryLocator = nil
        templatesDirectoryLocator = nil
        projectMapper = nil
        sideEffectDescriptorExecutor = nil
        subject = nil
    }

    func test_edit() throws {
        // Given
        let directory = try temporaryPath()
        let projectDescriptionPath = directory.appending(component: "ProjectDescription.framework")
        let project = Project.test(path: directory, name: "Edit")
        let graph = Graph.test(name: "Edit")
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
        projectEditorMapper.mapStub = (project, graph)
        var mappedProject: Project?
        projectMapper.mapStub = { project in
            mappedProject = project
            return (project, [])
        }
        var generatedProject: Project?
        generator.generateProjectSub = { project, _ in
            generatedProject = project
            return .test(xcodeprojPath: directory.appending(component: "Edit.xcodeproj"))
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
        XCTAssertEqual(project, mappedProject)

        XCTAssertEqual(generatedProject, project)
    }

    func test_edit_when_there_are_no_editable_files() throws {
        // Given
        let directory = try temporaryPath()
        let projectDescriptionPath = directory.appending(component: "ProjectDescription.framework")
        let project = Project.test(path: directory, name: "Edit")
        let graph = Graph.test(name: "Edit")
        let helpersDirectory = directory.appending(component: "ProjectDescriptionHelpers")
        try FileHandler.shared.createFolder(helpersDirectory)

        resourceLocator.projectDescriptionStub = { projectDescriptionPath }
        manifestFilesLocator.locateAllProjectManifestsStubs = []
        helpersDirectoryLocator.locateStub = helpersDirectory
        projectEditorMapper.mapStub = (project, graph)

        // When
        XCTAssertThrowsSpecific(try subject.edit(at: directory, in: directory), ProjectEditorError.noEditableFiles(directory))
    }
}
